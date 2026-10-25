"""cloudflared 管理层：运行时、证书、隧道、映射、进程与日志。

只依赖 Python 标准库，方便直接部署到任意 Linux 机器。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import uuid
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional


LOG_PREFIX = re.compile(
    r"^(?:\d{4}-\d{2}-\d{2}T\S+\s+)?(?:INF|ERR|WRN|DBG|FTL)\s+", re.IGNORECASE
)
QUICK_URL = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
LOGIN_URL = re.compile(r"https://[^\s\"'<>]*argotunnel[^\s\"'<>]*")
UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.IGNORECASE
)
HOSTNAME_RE = re.compile(
    r"^(?=.{4,253}$)([a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$"
)
TUNNEL_NAME_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$")


class ManagerError(Exception):
    """面向用户的错误信息。"""


def detect_platform() -> Dict[str, str]:
    import platform
    import sys

    system = sys.platform
    machine = (platform.machine() or "").lower()
    if system.startswith("win"):
        osname, ext = "windows", ".exe"
        arch = "arm64" if machine in ("aarch64", "arm64") else "amd64"
    elif system == "darwin":
        osname, ext = "darwin", ".tgz"
        arch = "arm64" if machine == "arm64" else "amd64"
    else:
        osname, ext = "linux", ""
        arch = "arm64" if machine in ("aarch64", "arm64") else "amd64"
    return {"os": osname, "arch": arch, "ext": ext, "binary": f"cloudflared{ext}"}


def download_url() -> str:
    info = detect_platform()
    return (
        "https://github.com/cloudflare/cloudflared/releases/latest/download/"
        f"cloudflared-{info['os']}-{info['arch']}{info['ext']}"
    )


@dataclass
class Endpoint:
    id: str
    hostname: str
    port: int
    scheme: str = "http"
    path: str = ""
    dns_routed: bool = False

    @property
    def service(self) -> str:
        return f"{self.scheme}://localhost:{self.port}"

    @property
    def public_url(self) -> str:
        return f"https://{self.hostname}{self.path}"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "hostname": self.hostname,
            "port": self.port,
            "scheme": self.scheme,
            "path": self.path,
            "dnsRouted": self.dns_routed,
        }

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> "Endpoint":
        return Endpoint(
            id=str(data.get("id") or uuid.uuid4().hex[:10]),
            hostname=str(data.get("hostname", "")).strip().lower(),
            port=int(data.get("port") or 0),
            scheme=data.get("scheme") if data.get("scheme") in ("http", "https") else "http",
            path=str(data.get("path") or "").strip(),
            dns_routed=bool(data.get("dnsRouted")),
        )


@dataclass
class Tunnel:
    id: str
    name: str
    credentials_path: str
    endpoints: List[Endpoint] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "credentialsPath": self.credentials_path,
            "endpoints": [e.to_dict() for e in self.endpoints],
            "createdAt": self.created_at,
        }

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> "Tunnel":
        return Tunnel(
            id=str(data["id"]),
            name=str(data.get("name", "tunnel")),
            credentials_path=str(data.get("credentialsPath", "")),
            endpoints=[Endpoint.from_dict(e) for e in data.get("endpoints", [])],
            created_at=float(data.get("createdAt") or time.time()),
        )


class LogHub:
    """带递增序号的日志环形缓冲，前端用 since 轮询增量。"""

    def __init__(self, capacity: int = 4000) -> None:
        self._entries: deque = deque(maxlen=capacity)
        self._lock = threading.Lock()
        self._seq = 0

    def add(self, source: str, message: str, level: str = "info") -> None:
        clean = LOG_PREFIX.sub("", message.strip()).strip()
        if not clean:
            return
        upper = message.upper()
        if level == "info":
            if " ERR " in upper or " FTL " in upper or upper.startswith("ERR "):
                level = "error"
            elif " WRN " in upper:
                level = "warn"
            elif " DBG " in upper:
                level = "debug"
        with self._lock:
            self._seq += 1
            self._entries.append(
                {
                    "seq": self._seq,
                    "time": time.time(),
                    "source": source,
                    "level": level,
                    "message": clean,
                }
            )

    def since(self, cursor: int, source: Optional[str] = None) -> Dict[str, Any]:
        with self._lock:
            items = [e for e in self._entries if e["seq"] > cursor]
            current = self._seq
        if source and source != "all":
            items = [e for e in items if e["source"] == source]
        return {"cursor": current, "entries": items[-800:]}

    def clear(self) -> None:
        with self._lock:
            self._entries.clear()

    def sources(self) -> List[str]:
        with self._lock:
            return sorted({e["source"] for e in self._entries})


class Runtime:
    def __init__(self) -> None:
        self.phase = "stopped"  # stopped|starting|connected|reconnecting|error
        self.pid: Optional[int] = None
        self.error: Optional[str] = None
        self.started_at: Optional[float] = None
        self.connections: set = set()
        self.process: Optional[subprocess.Popen] = None
        self.url: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "phase": self.phase,
            "pid": self.pid,
            "error": self.error,
            "startedAt": self.started_at,
            "connections": len(self.connections),
            "url": self.url,
        }


class CloudflaredManager:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = Path(data_dir)
        self.bin_dir = self.data_dir / "bin"
        self.creds_dir = self.data_dir / "credentials"
        self.configs_dir = self.data_dir / "configs"
        self.cert_path = self.data_dir / "cert.pem"
        self.state_file = self.data_dir / "state.json"
        # cloudflared 会在 $HOME 下创建 .cloudflared；服务账号往往没有可写家目录。
        self.home_dir = self.data_dir / "home"
        for path in (
            self.data_dir,
            self.bin_dir,
            self.creds_dir,
            self.configs_dir,
            self.home_dir,
        ):
            path.mkdir(parents=True, exist_ok=True)

        self.logs = LogHub()
        self.tunnels: List[Tunnel] = []
        self.runtimes: Dict[str, Runtime] = {}
        self.quick = Runtime()
        self.quick_port = 8080
        self.binary: Optional[str] = None
        self.version: Optional[str] = None
        self.login_proc: Optional[subprocess.Popen] = None
        self.login_url: Optional[str] = None
        self.login_error: Optional[str] = None
        self._login_cancelled = False
        self.remote_missing: set = set()
        self.missing_credentials: set = set()
        self._lock = threading.RLock()
        self._load()

    # ------------------------------------------------------------ 状态持久化

    def _load(self) -> None:
        if self.state_file.exists():
            try:
                raw = json.loads(self.state_file.read_text(encoding="utf-8"))
                self.tunnels = [Tunnel.from_dict(t) for t in raw.get("tunnels", [])]
                self.quick_port = int(raw.get("quickPort") or 8080)
            except Exception as exc:  # noqa: BLE001
                self.logs.add("系统", f"读取状态失败：{exc}", "warn")
        for tunnel in self.tunnels:
            self.runtimes.setdefault(tunnel.id, Runtime())
        self.missing_credentials = {
            t.id for t in self.tunnels if not Path(t.credentials_path).exists()
        }
        # 面板重启前完成过授权、但证书落在 $HOME/.cloudflared 的情况
        self._adopt_login_cert()

    def save(self) -> None:
        with self._lock:
            payload = {
                "version": 1,
                "quickPort": self.quick_port,
                "tunnels": [t.to_dict() for t in self.tunnels],
            }
            tmp = self.state_file.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
            tmp.replace(self.state_file)

    # ------------------------------------------------------------ 运行时

    def ensure_runtime(self) -> None:
        candidates = []
        env_bin = os.environ.get("CF_BIN")
        if env_bin:
            candidates.append(Path(env_bin))
        candidates.append(self.bin_dir / detect_platform()["binary"])
        found = shutil.which("cloudflared")
        if found:
            candidates.append(Path(found))
        for candidate in candidates:
            if candidate and candidate.exists():
                self.binary = str(candidate)
                self.version = self._probe_version()
                if self.version:
                    self.logs.add("系统", f"cloudflared 就绪：{candidate} (v{self.version})")
                    return
                self.binary = None
        self.logs.add("系统", "未找到可用的 cloudflared 运行时", "warn")

    def _probe_version(self) -> Optional[str]:
        try:
            out = subprocess.run(
                [self.binary, "--version"],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
                env=self._child_env(),
            )
        except Exception:  # noqa: BLE001
            return None
        match = re.search(r"version\s+(\S+)", out.stdout or "")
        return match.group(1) if match else None

    def install_runtime(self) -> str:
        """下载官方 cloudflared 到数据目录。"""
        if not self._idle():
            raise ManagerError("请先停止所有隧道再更新运行时")
        import urllib.request

        url = download_url()
        target = self.bin_dir / detect_platform()["binary"]
        if target.suffix.lower() == ".tgz":
            raise ManagerError("当前平台不支持自动下载，请手动安装 cloudflared")
        self.logs.add("系统", f"开始下载 cloudflared：{url}")
        tmp = target.with_suffix(".download")
        try:
            with urllib.request.urlopen(url, timeout=60) as resp, open(tmp, "wb") as fh:
                shutil.copyfileobj(resp, fh)
            if tmp.stat().st_size < 1024 * 1024:
                raise ManagerError("下载内容异常")
            os.chmod(tmp, 0o755)
            tmp.replace(target)
        except ManagerError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise ManagerError(f"下载失败：{exc}") from exc
        finally:
            if tmp.exists():
                tmp.unlink(missing_ok=True)
        self.binary = str(target)
        self.version = self._probe_version()
        if not self.version:
            raise ManagerError("下载的文件无法运行")
        self.logs.add("系统", f"cloudflared 已安装 v{self.version}")
        return self.version

    def _require_binary(self) -> str:
        if not self.binary:
            self.ensure_runtime()
        if not self.binary:
            raise ManagerError("cloudflared 运行时尚未就绪，请先安装")
        return self.binary

    def _child_env(self) -> Dict[str, str]:
        """把 HOME 指到数据目录：服务账号的家目录经常不存在或只读，
        cloudflared 启动时会 `mkdir $HOME/.cloudflared`，失败就直接退出。"""
        env = os.environ.copy()
        env["HOME"] = str(self.home_dir)
        return env

    # ------------------------------------------------------------ 账号

    def logged_in(self) -> bool:
        return self.cert_path.exists() and self.cert_path.stat().st_size > 100

    @property
    def default_cert_path(self) -> Path:
        return self.home_dir / ".cloudflared" / "cert.pem"

    def _adopt_login_cert(self, force: bool = False) -> bool:
        """`tunnel login` 不接受 --origincert，证书会写进 $HOME/.cloudflared/cert.pem，
        这里把它搬到面板统一使用的位置；force=True 时用新证书覆盖旧账号的证书。"""
        default = self.default_cert_path
        try:
            if not default.exists() or default.stat().st_size <= 100:
                return False
            if not force and self.logged_in():
                return False
            shutil.copyfile(default, self.cert_path)
            os.chmod(self.cert_path, 0o600)
            self.logs.add("系统", "已接收 Cloudflare 授权证书")
            return True
        except OSError as exc:  # noqa: BLE001
            self.logs.add("系统", f"接收授权证书失败：{exc}", "error")
            return False

    def start_login(self) -> Dict[str, Any]:
        if self.login_proc and self.login_proc.poll() is None:
            return {"started": False, "url": self.login_url}
        binary = self._require_binary()
        self.login_url = None
        self.login_error = None
        self._login_cancelled = False
        self.logs.add("系统", "启动 Cloudflare 授权流程，请在浏览器完成登录")
        proc = subprocess.Popen(
            [binary, "tunnel", "--origincert", str(self.cert_path), "login"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=self._child_env(),
        )
        self.login_proc = proc

        def reader() -> None:
            assert proc.stdout is not None
            tail: List[str] = []
            for line in proc.stdout:
                text = line.strip()
                if not text:
                    continue
                tail.append(text)
                del tail[:-6]
                match = LOGIN_URL.search(text)
                if match:
                    self.login_url = match.group(0)
                self.logs.add("登录", text)
            self._adopt_login_cert(force=True)
            if self.logged_in():
                self.logs.add("系统", "Cloudflare 账户授权成功")
            elif not self._login_cancelled:
                reason = tail[-1] if tail else "cloudflared 未输出授权链接"
                self.login_error = reason
                self.logs.add("系统", f"授权流程失败：{reason}", "error")
            self.login_proc = None

        threading.Thread(target=reader, daemon=True).start()
        return {"started": True, "url": None}

    def login_status(self) -> Dict[str, Any]:
        if not self.logged_in():
            # 授权可能刚落盘而登录进程已退出，顺手接管一次。
            self._adopt_login_cert()
        return {
            "loggedIn": self.logged_in(),
            "loggingIn": bool(self.login_proc and self.login_proc.poll() is None),
            "loginUrl": self.login_url,
            "error": self.login_error,
        }

    def cancel_login(self) -> None:
        proc = self.login_proc
        self._login_cancelled = True
        self.login_error = None
        if proc and proc.poll() is None:
            proc.terminate()
        self.login_proc = None
        self.logs.add("系统", "已取消 Cloudflare 授权")

    def logout(self) -> None:
        self.stop_all()
        for path in (self.cert_path, self.default_cert_path):
            if path.exists():
                path.unlink()
        self.logs.add("系统", "已退出 Cloudflare 账户")

    # ------------------------------------------------------------ 命令封装

    def _run(self, args: List[str], timeout: int = 90) -> "subprocess.CompletedProcess":
        binary = self._require_binary()
        try:
            return subprocess.run(
                [binary] + args,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                check=False,
                env=self._child_env(),
            )
        except subprocess.TimeoutExpired as exc:
            raise ManagerError(f"命令超时：{' '.join(args)}") from exc

    @staticmethod
    def friendly(text: str, fallback: str) -> str:
        lines = [LOG_PREFIX.sub("", line.strip()) for line in (text or "").splitlines()]
        lines = [line for line in lines if line]
        for line in reversed(lines):
            if "ERR" in line or "failed" in line.lower():
                return line[:260]
        return (lines[-1] if lines else fallback)[:260]

    def account_tunnels(self) -> int:
        return len(self._remote_tunnels())

    def _remote_tunnels(self) -> List[dict]:
        result = self._run(
            ["tunnel", "--origincert", str(self.cert_path), "list", "--output", "json"]
        )
        if result.returncode != 0:
            raise ManagerError(self.friendly(result.stdout + result.stderr, "无法读取云端隧道列表"))
        match = re.search(r"\[.*\]", result.stdout, re.S)
        if not match:
            return []
        return [item for item in json.loads(match.group(0)) if isinstance(item, dict)]

    @staticmethod
    def credentials_path_for(creds_dir: Path, tunnel_id: str, name: str) -> str:
        """云端允许隧道重名，凭证文件名带上 ID 前缀避免互相覆盖。"""
        safe = re.sub(r'[\\/:*?"<>|\s]+', "-", name).strip("-") or "tunnel"
        return str(creds_dir / f"{safe}-{tunnel_id.replace('-', '')[:8]}.json")

    def fetch_credentials(self, tunnel_id: str, credentials_path: str) -> None:
        Path(credentials_path).parent.mkdir(parents=True, exist_ok=True)
        result = self._run(
            [
                "tunnel",
                "--origincert",
                str(self.cert_path),
                "token",
                "--credentials-file",
                credentials_path,
                tunnel_id,
            ]
        )
        if result.returncode != 0 or not Path(credentials_path).exists():
            raise ManagerError(
                self.friendly(result.stdout + result.stderr, "无法从云端取回该隧道的凭证")
            )
        self.logs.add("系统", f"已取回隧道凭证：{tunnel_id[:8]}…")

    def sync_tunnels(self) -> Dict[str, int]:
        """把云端已有隧道导入面板，并补齐本机缺失的凭证。"""
        if not self.logged_in():
            raise ManagerError("请先登录 Cloudflare 账户")
        remote = self._remote_tunnels()
        imported = 0
        repaired = 0
        ids = set()
        for item in remote:
            tunnel_id = str(item.get("id") or item.get("UUID") or "")
            if not tunnel_id:
                continue
            name = str(item.get("name") or "").strip() or tunnel_id[:8]
            ids.add(tunnel_id)
            tunnel = next((t for t in self.tunnels if t.id == tunnel_id), None)
            if tunnel is None:
                tunnel = Tunnel(
                    id=tunnel_id,
                    name=name,
                    credentials_path=self.credentials_path_for(self.creds_dir, tunnel_id, name),
                )
                self.tunnels.append(tunnel)
                self.runtimes[tunnel_id] = Runtime()
                imported += 1
                self.logs.add("系统", f"从云端导入隧道「{name}」")
            elif tunnel.name != name:
                tunnel.name = name
            if not Path(tunnel.credentials_path).exists():
                try:
                    self.fetch_credentials(tunnel_id, tunnel.credentials_path)
                    repaired += 1
                except ManagerError as exc:
                    self.logs.add("系统", f"「{name}」凭证取回失败：{exc}", "error")
        self.remote_missing = {t.id for t in self.tunnels if t.id not in ids}
        self.refresh_missing_credentials()
        self.save()
        return {"cloud": len(remote), "imported": imported, "repaired": repaired}

    def refresh_missing_credentials(self) -> None:
        self.missing_credentials = {
            t.id for t in self.tunnels if not Path(t.credentials_path).exists()
        }

    def repair_credentials(self, tunnel_id: str) -> None:
        tunnel = self._find(tunnel_id)
        if not self.logged_in():
            raise ManagerError("请先登录 Cloudflare 账户")
        self.fetch_credentials(tunnel_id, tunnel.credentials_path)
        self.refresh_missing_credentials()
        self.save()

    # ------------------------------------------------------------ 隧道

    def create_tunnel(self, name: str) -> Tunnel:
        name = (name or "").strip().lower()
        if not TUNNEL_NAME_RE.match(name):
            raise ManagerError("隧道名称只允许小写字母、数字与连字符")
        if not self.logged_in():
            raise ManagerError("请先登录 Cloudflare 账户")
        if any(t.name == name for t in self.tunnels):
            raise ManagerError("已存在同名隧道")
        creds = self.creds_dir / f"{name}-{int(time.time())}.json"
        result = self._run(
            [
                "tunnel",
                "--origincert",
                str(self.cert_path),
                "create",
                "--credentials-file",
                str(creds),
                name,
            ]
        )
        if result.returncode != 0:
            raise ManagerError(self.friendly(result.stdout + result.stderr, "创建隧道失败"))
        tunnel_id = None
        try:
            tunnel_id = json.loads(creds.read_text(encoding="utf-8")).get("TunnelID")
        except Exception:  # noqa: BLE001
            pass
        if not tunnel_id:
            match = UUID_RE.search(result.stdout + result.stderr)
            tunnel_id = match.group(0) if match else None
        if not tunnel_id:
            raise ManagerError("无法解析新建隧道的 ID")
        tunnel = Tunnel(id=tunnel_id, name=name, credentials_path=str(creds))
        self.tunnels.append(tunnel)
        self.runtimes[tunnel_id] = Runtime()
        self.save()
        self.logs.add("系统", f"已创建隧道「{name}」")
        return tunnel

    def _find(self, tunnel_id: str) -> Tunnel:
        for tunnel in self.tunnels:
            if tunnel.id == tunnel_id:
                return tunnel
        raise ManagerError("隧道不存在")

    def delete_tunnel(self, tunnel_id: str) -> None:
        tunnel = self._find(tunnel_id)
        self.stop_tunnel(tunnel_id)
        if self.logged_in():
            self._run(["tunnel", "--origincert", str(self.cert_path), "cleanup", tunnel_id], 60)
            result = self._run(
                ["tunnel", "--origincert", str(self.cert_path), "delete", "-f", tunnel_id]
            )
            if result.returncode != 0:
                raise ManagerError(self.friendly(result.stdout + result.stderr, "云端删除失败"))
        self.tunnels.remove(tunnel)
        self.runtimes.pop(tunnel_id, None)
        self.remote_missing.discard(tunnel_id)
        self.missing_credentials.discard(tunnel_id)
        for path in (Path(tunnel.credentials_path), self.configs_dir / f"{tunnel_id}.yml"):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        self.save()
        self.logs.add("系统", f"已删除隧道「{tunnel.name}」（DNS 记录需自行清理）")

    def add_endpoint(self, tunnel_id: str, payload: Dict[str, Any]) -> Endpoint:
        tunnel = self._find(tunnel_id)
        endpoint = Endpoint.from_dict(payload)
        self._validate_endpoint(endpoint)
        if any(
            e.hostname == endpoint.hostname and e.path == endpoint.path
            for e in tunnel.endpoints
        ):
            raise ManagerError("该域名与路径的映射已存在")
        tunnel.endpoints.append(endpoint)
        self._mark_pending(tunnel_id)
        self.save()
        self.logs.add("系统", f"已添加映射 {endpoint.public_url} → {endpoint.service}")
        if payload.get("dns") and self.logged_in():
            try:
                self.route_dns(tunnel_id, endpoint.id, bool(payload.get("overwrite")))
            except ManagerError as exc:
                self.logs.add("系统", str(exc), "error")
        return endpoint

    def update_endpoint(self, tunnel_id: str, endpoint_id: str, payload: Dict[str, Any]) -> Endpoint:
        tunnel = self._find(tunnel_id)
        current = next((e for e in tunnel.endpoints if e.id == endpoint_id), None)
        if not current:
            raise ManagerError("映射不存在")
        updated = Endpoint.from_dict({**payload, "id": endpoint_id})
        self._validate_endpoint(updated)
        if updated.hostname != current.hostname:
            updated.dns_routed = False
        tunnel.endpoints[tunnel.endpoints.index(current)] = updated
        self._mark_pending(tunnel_id)
        self.save()
        return updated

    def remove_endpoint(self, tunnel_id: str, endpoint_id: str) -> None:
        tunnel = self._find(tunnel_id)
        before = len(tunnel.endpoints)
        tunnel.endpoints = [e for e in tunnel.endpoints if e.id != endpoint_id]
        if len(tunnel.endpoints) == before:
            raise ManagerError("映射不存在")
        self._mark_pending(tunnel_id)
        self.save()

    @staticmethod
    def _validate_endpoint(endpoint: Endpoint) -> None:
        if not HOSTNAME_RE.match(endpoint.hostname):
            raise ManagerError("域名格式不正确，例如 app.example.com")
        if not 1 <= endpoint.port <= 65535:
            raise ManagerError("端口需在 1–65535 之间")
        if endpoint.path and not endpoint.path.startswith("/"):
            raise ManagerError("路径需以 / 开头")

    def _mark_pending(self, tunnel_id: str) -> None:
        runtime = self.runtimes.get(tunnel_id)
        if runtime and runtime.phase != "stopped":
            runtime.error = "配置已修改，重启隧道后生效"

    def route_dns(self, tunnel_id: str, endpoint_id: str, overwrite: bool = False) -> bool:
        tunnel = self._find(tunnel_id)
        endpoint = next((e for e in tunnel.endpoints if e.id == endpoint_id), None)
        if not endpoint:
            raise ManagerError("映射不存在")
        if not self.logged_in():
            raise ManagerError("请先登录 Cloudflare 账户")
        args = ["tunnel", "--origincert", str(self.cert_path), "route", "dns"]
        if overwrite:
            args.append("--overwrite-dns")
        args += [tunnel_id, endpoint.hostname]
        self.logs.add("系统", f"正在为 {endpoint.hostname} 创建 DNS 记录")
        result = self._run(args)
        if result.returncode != 0:
            message = self.friendly(result.stdout + result.stderr, "DNS 配置失败")
            self.logs.add("系统", message, "error")
            raise ManagerError(message)
        endpoint.dns_routed = True
        self.save()
        self.logs.add("系统", f"DNS 已指向隧道：{endpoint.hostname}")
        return True

    def route_all_dns(self, tunnel_id: str) -> int:
        tunnel = self._find(tunnel_id)
        count = 0
        for endpoint in list(tunnel.endpoints):
            if not endpoint.dns_routed:
                try:
                    self.route_dns(tunnel_id, endpoint.id, False)
                    count += 1
                except ManagerError:
                    continue
        return count

    # ------------------------------------------------------------ 进程

    def _write_config(self, tunnel: Tunnel) -> Path:
        lines = [
            "# generated by cf-tunnel-webui",
            f"tunnel: {tunnel.id}",
            f"credentials-file: '{tunnel.credentials_path}'",
            "ingress:",
        ]
        for endpoint in tunnel.endpoints:
            lines.append(f"  - hostname: {endpoint.hostname}")
            if endpoint.path:
                lines.append(f"    path: {endpoint.path}")
            lines.append(f"    service: {endpoint.service}")
        lines.append("  - service: http_status:404")
        path = self.configs_dir / f"{tunnel.id}.yml"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def start_tunnel(self, tunnel_id: str) -> None:
        tunnel = self._find(tunnel_id)
        runtime = self.runtimes.setdefault(tunnel_id, Runtime())
        if runtime.phase != "stopped":
            return
        if not tunnel.endpoints:
            raise ManagerError("请先添加至少一个端口映射")
        if not Path(tunnel.credentials_path).exists():
            # 换机器或清空过数据：先尝试从云端取回同一隧道的凭证。
            try:
                self.fetch_credentials(tunnel_id, tunnel.credentials_path)
            except ManagerError as exc:
                self.refresh_missing_credentials()
                raise ManagerError(f"{exc}（无需重建隧道，可在卡片上重试取回凭证）") from None
            self.missing_credentials.discard(tunnel_id)
        binary = self._require_binary()
        config = self._write_config(tunnel)
        runtime.phase = "starting"
        runtime.error = None
        runtime.started_at = time.time()
        runtime.connections = set()
        self.logs.add("系统", f"正在启动隧道「{tunnel.name}」")
        proc = subprocess.Popen(
            [
                binary,
                "tunnel",
                "--config",
                str(config),
                "--origincert",
                str(self.cert_path),
                "--no-autoupdate",
                "run",
                tunnel_id,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=self._child_env(),
        )
        runtime.process = proc
        runtime.pid = proc.pid
        self._spawn_reader(proc, tunnel.name, runtime)

    def _spawn_reader(self, proc: subprocess.Popen, source: str, runtime: Runtime) -> None:
        def reader() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.rstrip()
                if not line.strip():
                    continue
                self.logs.add(source, line)
                index = re.search(r"connIndex=(\d+)", line)
                idx = int(index.group(1)) if index else None
                if "Registered tunnel connection" in line and idx is not None:
                    runtime.connections.add(idx)
                    runtime.phase = "connected"
                elif "Unregistered tunnel connection" in line and idx is not None:
                    runtime.connections.discard(idx)
                    if not runtime.connections and runtime.phase == "connected":
                        runtime.phase = "reconnecting"
                elif "Retrying connection" in line and runtime.phase == "connected":
                    runtime.phase = "reconnecting"
                elif "ERR" in line:
                    runtime.error = self.friendly(line, runtime.error or "")
            code = proc.wait()
            if runtime.process is proc:
                runtime.process = None
                runtime.pid = None
                runtime.connections = set()
                if runtime.phase != "stopped":
                    runtime.phase = "stopped" if code == 0 else "error"
                    if code != 0:
                        runtime.error = f"进程退出（代码 {code}）"
                        self.logs.add(source, f"进程退出，代码 {code}", "error")

        threading.Thread(target=reader, daemon=True).start()

    def stop_tunnel(self, tunnel_id: str) -> None:
        runtime = self.runtimes.get(tunnel_id)
        if not runtime:
            return
        proc = runtime.process
        runtime.phase = "stopped"
        runtime.pid = None
        runtime.connections = set()
        runtime.error = None
        runtime.process = None
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        tunnel = next((t for t in self.tunnels if t.id == tunnel_id), None)
        if tunnel:
            self.logs.add("系统", f"已停止隧道「{tunnel.name}」")

    def start_quick(self, port: int) -> None:
        if self.quick.phase != "stopped":
            return
        if not 1 <= int(port) <= 65535:
            raise ManagerError("端口需在 1–65535 之间")
        binary = self._require_binary()
        self.quick_port = int(port)
        self.save()
        self.quick.phase = "starting"
        self.quick.url = None
        self.quick.error = None
        self.quick.started_at = time.time()
        self.logs.add("系统", f"正在创建临时隧道 → localhost:{port}")
        proc = subprocess.Popen(
            [binary, "tunnel", "--no-autoupdate", "--url", f"http://localhost:{port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=self._child_env(),
        )
        self.quick.process = proc
        self.quick.pid = proc.pid

        def reader() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.rstrip()
                if not line.strip():
                    continue
                self.logs.add("临时隧道", line)
                match = QUICK_URL.search(line)
                if match and "api.trycloudflare" not in match.group(0):
                    if self.quick.url != match.group(0):
                        self.quick.url = match.group(0)
                        self.quick.phase = "connected"
                        self.logs.add("系统", f"临时公网地址：{self.quick.url}")
            code = proc.wait()
            if self.quick.process is proc:
                self.quick.process = None
                self.quick.pid = None
                self.quick.url = None
                if self.quick.phase != "stopped":
                    self.quick.phase = "stopped" if code == 0 else "error"
                    if code != 0:
                        self.quick.error = f"进程退出（代码 {code}）"

        threading.Thread(target=reader, daemon=True).start()

    def stop_quick(self) -> None:
        proc = self.quick.process
        self.quick.phase = "stopped"
        self.quick.pid = None
        self.quick.url = None
        self.quick.process = None
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        self.logs.add("系统", "已停止临时隧道")

    def stop_all(self) -> None:
        self.stop_quick()
        for tunnel_id in list(self.runtimes):
            self.stop_tunnel(tunnel_id)

    def _idle(self) -> bool:
        if self.quick.process:
            return False
        return all(r.process is None for r in self.runtimes.values())

    # ------------------------------------------------------------ 快照

    def snapshot(self) -> Dict[str, Any]:
        tunnels = []
        for tunnel in self.tunnels:
            runtime = self.runtimes.get(tunnel.id, Runtime())
            tunnels.append(
                {
                    **tunnel.to_dict(),
                    "runtime": runtime.to_dict(),
                    "unrouted": sum(1 for e in tunnel.endpoints if not e.dns_routed),
                    "credsMissing": tunnel.id in self.missing_credentials
                    or not Path(tunnel.credentials_path).exists(),
                    "remoteMissing": tunnel.id in self.remote_missing,
                }
            )
        return {
            "ready": bool(self.binary and self.version),
            "binary": self.binary,
            "version": self.version,
            "loggedIn": self.logged_in(),
            "loggingIn": bool(self.login_proc and self.login_proc.poll() is None),
            "loginUrl": self.login_url,
            "loginError": self.login_error,
            "dataDir": str(self.data_dir),
            "platform": detect_platform(),
            "quick": self.quick.to_dict(),
            "quickPort": self.quick_port,
            "tunnels": tunnels,
            "totals": {
                "tunnels": len(self.tunnels),
                "online": sum(1 for t in tunnels if t["runtime"]["phase"] != "stopped"),
                "endpoints": sum(len(t["endpoints"]) for t in tunnels),
                "connections": sum(
                    t["runtime"]["connections"] for t in tunnels
                )
                + (1 if self.quick.phase == "connected" else 0),
            },
        }
