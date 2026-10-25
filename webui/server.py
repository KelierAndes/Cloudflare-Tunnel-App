#!/usr/bin/env python3
"""Cloudflare Tunnel Web 管理面板。

只使用 Python 标准库，适合直接部署在 Debian / Ubuntu 服务器上：

    python3 server.py --host 0.0.0.0 --port 8788 --data-dir /var/lib/cf-tunnel-webui

浏览器打开 http://<host>:<port>/?token=<token>，token 会打印在启动日志里。
"""

from __future__ import annotations

import argparse
import hmac
import json
import mimetypes
import re
import secrets
import sys
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cfmanager import CloudflaredManager, ManagerError  # noqa: E402

STATIC_DIR = Path(__file__).resolve().parent / "static"
TOKEN_COOKIE = "cf_tunnel_token"


def load_token(data_dir: Path, provided: str | None) -> str:
    if provided:
        return provided
    token_file = data_dir / "token"
    if token_file.exists():
        value = token_file.read_text(encoding="utf-8").strip()
        if value:
            return value
    value = secrets.token_urlsafe(18)
    token_file.write_text(value, encoding="utf-8")
    token_file.chmod(0o600)
    return value


class Handler(BaseHTTPRequestHandler):
    server_version = "CfTunnelWebUI/1.0"
    manager: CloudflaredManager  # injected
    token: str = ""

    # ------------------------------------------------------------ helpers

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        sys.stderr.write("[webui] %s - %s\n" % (self.address_string(), fmt % args))

    def _json(self, payload, status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _text(self, text: str, status: int = HTTPStatus.OK) -> None:
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        header = self.headers.get("X-Auth-Token", "")
        if hmac.compare_digest(header, self.token):
            return True
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        morsel = cookie.get(TOKEN_COOKIE)
        if morsel and hmac.compare_digest(morsel.value, self.token):
            return True
        query = parse_qs(urlparse(self.path).query)
        if hmac.compare_digest((query.get("token") or [""])[0], self.token):
            return True
        return False

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise ManagerError(f"请求体不是合法 JSON：{exc}") from exc
        return data if isinstance(data, dict) else {}

    def _static(self, name: str) -> None:
        target = (STATIC_DIR / name).resolve()
        if not str(target).startswith(str(STATIC_DIR.resolve())) or not target.is_file():
            self._text("not found", HTTPStatus.NOT_FOUND)
            return
        mime = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        if mime.startswith("text/") or mime in ("application/javascript",):
            mime += "; charset=utf-8"
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    # ------------------------------------------------------------ routing

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/healthz":
            self._json({"ok": True})
            return
        if not self._authorized():
            self._json({"error": "未授权：请在地址后加上 ?token=<token>"}, HTTPStatus.UNAUTHORIZED)
            return
        if path in ("/", "/index.html"):
            query = parse_qs(urlparse(self.path).query)
            if query.get("token"):
                self.send_response(HTTPStatus.FOUND)
                self.send_header(
                    "Set-Cookie",
                    f"{TOKEN_COOKIE}={self.token}; Path=/; HttpOnly; SameSite=Lax",
                )
                self.send_header("Location", "/")
                self.end_headers()
                return
            self._static("index.html")
            return
        if path.startswith("/static/"):
            self._static(path[len("/static/") :])
            return
        if path == "/api/state":
            self._json(self.manager.snapshot())
            return
        if path == "/api/logs":
            query = parse_qs(urlparse(self.path).query)
            cursor = int((query.get("since") or ["0"])[0])
            source = (query.get("source") or ["all"])[0]
            self._json(self.manager.logs.since(cursor, source))
            return
        self._json({"error": "未知接口"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        try:
            self._post()
        except ManagerError as exc:
            self._json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except Exception as exc:  # noqa: BLE001
            self._json({"error": f"服务器错误：{exc}"}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def _post(self) -> None:
        if not self._authorized():
            self._json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
            return
        path = urlparse(self.path).path
        body = self._body()
        manager = self.manager

        def tunnel_id(pattern: str) -> str | None:
            match = re.match(pattern, path)
            return match.group("id") if match else None

        if path == "/api/login/start":
            self._json(manager.start_login())
        elif path == "/api/login/cancel":
            manager.cancel_login()
            self._json({"ok": True})
        elif path == "/api/login/check":
            self._json(manager.login_status())
        elif path == "/api/logout":
            manager.logout()
            self._json(manager.snapshot())
        elif path in ("/api/account/check", "/api/sync"):
            self._json(manager.sync_tunnels())
        elif path == "/api/runtime/install":
            self._json({"version": manager.install_runtime()})
        elif path == "/api/tunnels":
            tunnel = manager.create_tunnel(str(body.get("name", "")))
            self._json(tunnel.to_dict())
        elif path == "/api/quick/start":
            manager.start_quick(int(body.get("port") or manager.quick_port))
            self._json(manager.quick.to_dict())
        elif path == "/api/quick/stop":
            manager.stop_quick()
            self._json({"ok": True})
        elif path == "/api/logs/clear":
            manager.logs.clear()
            self._json({"ok": True})
        elif match := re.match(
            r"^/api/tunnels/(?P<id>[^/]+)/(?P<action>start|stop|dns|credentials)$", path
        ):
            tid, action = match.group("id"), match.group("action")
            if action == "start":
                manager.start_tunnel(tid)
                self._json({"ok": True})
            elif action == "stop":
                manager.stop_tunnel(tid)
                self._json({"ok": True})
            elif action == "credentials":
                manager.repair_credentials(tid)
                self._json({"ok": True})
            else:
                self._json({"routed": manager.route_all_dns(tid)})
        elif match := re.match(
            r"^/api/tunnels/(?P<id>[^/]+)/endpoints/(?P<eid>[^/]+)$", path
        ):
            manager.update_endpoint(match.group("id"), match.group("eid"), body)
            self._json({"ok": True})
        elif match := re.match(
            r"^/api/tunnels/(?P<id>[^/]+)/endpoints/(?P<eid>[^/]+)/dns$", path
        ):
            manager.route_dns(
                match.group("id"), match.group("eid"), bool(body.get("overwrite"))
            )
            self._json({"ok": True})
        elif path.startswith("/api/tunnels/") and path.endswith("/endpoints"):
            tid = path[len("/api/tunnels/") : -len("/endpoints")]
            self._json(manager.add_endpoint(tid, body).to_dict())
        else:
            self._json({"error": "未知接口"}, HTTPStatus.NOT_FOUND)

    def do_DELETE(self) -> None:  # noqa: N802
        try:
            self._delete()
        except ManagerError as exc:
            self._json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except Exception as exc:  # noqa: BLE001
            self._json({"error": f"服务器错误：{exc}"}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def _delete(self) -> None:
        if not self._authorized():
            self._json({"error": "未授权"}, HTTPStatus.UNAUTHORIZED)
            return
        path = urlparse(self.path).path
        manager = self.manager
        if match := re.match(r"^/api/tunnels/(?P<id>[^/]+)/endpoints/(?P<eid>[^/]+)$", path):
            manager.remove_endpoint(match.group("id"), match.group("eid"))
            self._json({"ok": True})
            return
        if match := re.match(r"^/api/tunnels/(?P<id>[^/]+)$", path):
            manager.delete_tunnel(match.group("id"))
            self._json({"ok": True})
            return
        self._json({"error": "未知接口"}, HTTPStatus.NOT_FOUND)


def main() -> int:
    parser = argparse.ArgumentParser(description="Cloudflare Tunnel Web 管理面板")
    default_data = Path.home() / ".cf-tunnel-webui"
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8788)
    parser.add_argument("--data-dir", type=Path, default=default_data)
    parser.add_argument("--token", default=None, help="访问令牌，缺省时自动生成并保存")
    args = parser.parse_args()

    data_dir = args.data_dir.expanduser().resolve()
    data_dir.mkdir(parents=True, exist_ok=True)
    token = load_token(data_dir, args.token)

    manager = CloudflaredManager(data_dir)
    manager.ensure_runtime()
    Handler.manager = manager
    Handler.token = token

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    print(f"[cf-tunnel-webui] 数据目录：{data_dir}", flush=True)
    print(f"[cf-tunnel-webui] cloudflared：{manager.binary or '未安装'}", flush=True)
    print(f"[cf-tunnel-webui] 面板地址：http://{args.host}:{args.port}/?token={token}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        manager.stop_all()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
