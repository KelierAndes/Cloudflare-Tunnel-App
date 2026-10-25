#!/usr/bin/env python3
"""用假 cloudflared 验证云端隧道导入与凭证取回。

    python3 webui/tests/test_sync.py
"""

from __future__ import annotations

import os
import pathlib
import stat
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from cfmanager import CloudflaredManager, ManagerError  # noqa: E402


def main() -> int:
    fake = HERE / "fake_cloudflared.sh"
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    os.environ["CF_BIN"] = str(fake)

    with tempfile.TemporaryDirectory() as tmp:
        data = pathlib.Path(tmp) / "data"
        data.mkdir()
        (data / "cert.pem").write_text("x" * 200, encoding="utf-8")

        manager = CloudflaredManager(data)
        manager.ensure_runtime()
        assert manager.version == "0.0.0-test", manager.version
        assert manager.logged_in()

        result = manager.sync_tunnels()
        # 首次同步：导入 2 条，并顺带取回这 2 条的凭证
        assert result == {"cloud": 2, "imported": 2, "repaired": 2}, result
        assert len(manager.tunnels) == 2, manager.tunnels
        creds = [pathlib.Path(t.credentials_path) for t in manager.tunnels]
        assert all(path.exists() and path.stat().st_size > 0 for path in creds), creds
        # 云端允许重名：凭证文件不能互相覆盖
        assert len({path.name for path in creds}) == 2, [p.name for p in creds]
        assert not manager.missing_credentials
        assert not manager.remote_missing

        # 换机器场景：凭证丢失后同步应自动取回
        creds[0].unlink()
        manager.refresh_missing_credentials()
        assert manager.missing_credentials == {manager.tunnels[0].id}
        second = manager.sync_tunnels()
        assert second == {"cloud": 2, "imported": 0, "repaired": 1}, second
        assert not manager.missing_credentials

        # 手动取回接口
        creds[1].unlink()
        manager.refresh_missing_credentials()
        manager.repair_credentials(manager.tunnels[1].id)
        assert not manager.missing_credentials

        # 云端已删除的本地隧道会被标记，而不是被悄悄删掉
        manager.tunnels.append(
            type(manager.tunnels[0])(
                id="deadbeef-0000-0000-0000-000000000000",
                name="ghost",
                credentials_path=str(data / "credentials" / "ghost.json"),
            )
        )
        manager.runtimes["deadbeef-0000-0000-0000-000000000000"] = type(manager.quick)()
        manager.sync_tunnels()
        assert "deadbeef-0000-0000-0000-000000000000" in manager.remote_missing
        assert len(manager.tunnels) == 3

        # 未登录时同步应给出中文提示
        (data / "cert.pem").unlink()
        try:
            manager.sync_tunnels()
        except ManagerError as exc:
            assert "登录" in str(exc), exc
        else:
            raise AssertionError("未登录时同步应当报错")

    # 授权流程：URL 抓取、HOME 重定向、失败原因回传
    with tempfile.TemporaryDirectory() as tmp:
        data = pathlib.Path(tmp) / "data"
        data.mkdir()
        home_out = pathlib.Path(tmp) / "home.txt"
        os.environ["FAKE_HOME_OUT"] = str(home_out)

        manager = CloudflaredManager(data)
        manager.ensure_runtime()
        assert not manager.logged_in()

        started = manager.start_login()
        assert started["started"], started
        status = {}
        for _ in range(50):
            status = manager.login_status()
            if status["loginUrl"] or status["error"]:
                break
            time.sleep(0.1)
        assert status["loginUrl"] and "argotunnel" in status["loginUrl"], status
        assert status["loggingIn"], status
        # 服务账号家目录不可用时，HOME 必须指到数据目录下
        assert home_out.read_text(encoding="utf-8") == str(data / "home")
        manager.cancel_login()
        assert not manager.login_status()["loggingIn"]
        assert manager.login_status()["error"] is None

        # cloudflared 起不来时把真实原因带回面板，而不是空白等待
        os.environ["FAKE_LOGIN_FAIL"] = (
            "mkdir /home/gone/.cloudflared: no such file or directory"
        )
        manager.start_login()
        status = {}
        for _ in range(50):
            status = manager.login_status()
            if status["error"]:
                break
            time.sleep(0.1)
        assert "no such file" in (status["error"] or ""), status
        assert not status["loggingIn"], status
        os.environ.pop("FAKE_LOGIN_FAIL", None)

        # 浏览器授权完成后 cloudflared 把证书写进 $HOME/.cloudflared，
        # 面板要接管到 cert_path，否则会一直显示未登录
        os.environ["FAKE_LOGIN_OK"] = "1"
        manager.start_login()
        for _ in range(50):
            manager.login_status()
            if manager.logged_in():
                break
            time.sleep(0.1)
        assert manager.logged_in(), "授权完成后应接管 $HOME/.cloudflared/cert.pem"
        assert "ARGO TUNNEL TOKEN" in manager.cert_path.read_text(encoding="utf-8")
        assert manager.login_status()["loggedIn"]
        os.environ.pop("FAKE_LOGIN_OK", None)

        # 退出登录要同时清掉两份证书，否则会被重新接管
        manager.logout()
        assert not manager.logged_in()
        assert not manager.default_cert_path.exists()
        os.environ.pop("FAKE_HOME_OUT", None)

    print("test_sync: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
