#!/usr/bin/env bash
# 在 Debian / Ubuntu 上安装 Cloudflare Tunnel Web 管理面板。
# 用法： bash webui/install.sh [--port 8788] [--host 0.0.0.0]
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/cf-tunnel-webui"
DATA_DIR="/var/lib/cf-tunnel-webui"
RUN_USER="${SUDO_USER:-$(id -un)}"
HOST="0.0.0.0"
PORT="8788"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
done

echo "==> 安装目录 $APP_DIR，数据目录 $DATA_DIR，运行用户 $RUN_USER"
RUN_GROUP="$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")"
sudo mkdir -p "$APP_DIR" "$DATA_DIR/bin" "$DATA_DIR/credentials" "$DATA_DIR/configs"
sudo cp -r "$SRC/server.py" "$SRC/cfmanager.py" "$SRC/static" "$APP_DIR/"
sudo chown -R "$RUN_USER:$RUN_GROUP" "$APP_DIR" "$DATA_DIR"

if [[ ! -x "$DATA_DIR/bin/cloudflared" ]]; then
  echo "==> 下载 cloudflared 官方运行时"
  curl -fL --retry 3 -o "$DATA_DIR/bin/cloudflared" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$(dpkg --print-architecture)"
  chmod 755 "$DATA_DIR/bin/cloudflared"
fi

echo "==> 写入 systemd 服务 cf-tunnel-webui"
sudo tee /etc/systemd/system/cf-tunnel-webui.service > /dev/null <<UNIT
[Unit]
Description=Cloudflare Tunnel Web 管理面板
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Environment=CF_BIN=${DATA_DIR}/bin/cloudflared
ExecStart=/usr/bin/python3 ${APP_DIR}/server.py --host ${HOST} --port ${PORT} --data-dir ${DATA_DIR}
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now cf-tunnel-webui
sleep 2
sudo systemctl --no-pager --full status cf-tunnel-webui | head -8 || true

echo
echo "面板地址： http://$(hostname -I | awk '{print $1}'):${PORT}/?token=$(cat "$DATA_DIR/token")"
echo "日志：     sudo journalctl -u cf-tunnel-webui -f"
