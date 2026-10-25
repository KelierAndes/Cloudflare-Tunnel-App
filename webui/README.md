# Cloudflare Tunnel · Linux Web 管理面板

一个只依赖 Python 标准库的 Web 控制台，用来在 Linux 服务器上管理 cloudflared：
登录 Cloudflare、创建命名隧道、域名 → 本机端口映射、写入 DNS CNAME、启停与实时日志。
功能与 Flutter 桌面端一致，适合没有图形界面的机器。

## 一键部署（Debian / Ubuntu）

```bash
git clone <你的仓库> && cd cf_tunnel_manager
bash webui/install.sh                 # 默认 0.0.0.0:8788
bash webui/install.sh --port 9000     # 自定义端口
```

install.sh 会：

1. 把代码安装到 `/opt/cf-tunnel-webui`，数据放到 `/var/lib/cf-tunnel-webui`
2. 从官方 GitHub Releases 下载对应架构的 cloudflared 到 `bin/cloudflared`
3. 写入并启动 systemd 服务 `cf-tunnel-webui`（开机自启、崩溃自动重启）
4. 打印带令牌的访问地址

常用运维命令：

```bash
systemctl status cf-tunnel-webui
journalctl -u cf-tunnel-webui -f
cat /var/lib/cf-tunnel-webui/token          # 查看访问令牌
sudo systemctl restart cf-tunnel-webui
```

## 手动运行

```bash
python3 webui/server.py --host 127.0.0.1 --port 8788 --data-dir ~/.cf-tunnel-webui
# 可选环境变量 CF_BIN=/usr/local/bin/cloudflared 指定已有的可执行文件
```

## 访问与安全

- 首次启动会在数据目录生成 `token` 文件并打印在日志里。
- 打开 `http://<服务器IP>:8788/?token=<token>`，令牌会写入 HttpOnly Cookie，
  之后所有 `/api/*` 请求都通过 Cookie 或 `X-Auth-Token` 头校验，未授权返回 401。
- 面板本身是 HTTP。建议只在可信内网暴露端口，或前置 Nginx + HTTPS，
  例如 `location / { proxy_pass http://127.0.0.1:8788; }`。
- 令牌等同于管理权限（可创建隧道、改 DNS），请勿泄露；更换方式：
  删除 `token` 文件后重启服务。

## HTTP API

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/healthz` | 存活探测（无需令牌） |
| GET | `/api/state` | 运行时、账户、隧道与统计快照 |
| GET | `/api/logs?since=<seq>&source=<名称>` | 增量日志，返回 `cursor` 与 `entries` |
| POST | `/api/login/start` `/api/login/cancel` `/api/login/check` | 无头授权流程（复制返回的链接到任意浏览器打开） |
| POST | `/api/sync`（旧路径 `/api/account/check` 同义） | 列出云端隧道并导入本地、自动取回缺失凭证，返回 `{cloud,imported,repaired}` |
| POST | `/api/logout` | 删除证书并停止全部隧道 |
| POST | `/api/runtime/install` | 下载官方 cloudflared 到数据目录 |
| POST | `/api/tunnels` | 新建命名隧道 `{name}` |
| DELETE | `/api/tunnels/<id>` | 删除隧道（云端 + 本机凭证） |
| POST | `/api/tunnels/<id>/start` `/stop` `/dns` | 启停隧道 / 为全部映射补建 DNS |
| POST | `/api/tunnels/<id>/credentials` | 从云端取回该隧道的凭证（换机、清理数据后无需重建） |
| POST | `/api/tunnels/<id>/endpoints` | 新增映射 `{hostname,port,scheme,path,dns,overwrite}` |
| PUT | `/api/tunnels/<id>/endpoints/<eid>` | 修改映射 |
| DELETE | `/api/tunnels/<id>/endpoints/<eid>` | 删除映射 |
| POST | `/api/tunnels/<id>/endpoints/<eid>/dns` | 为该映射创建 CNAME `{overwrite}` |
| POST | `/api/quick/start` `/api/quick/stop` | 临时隧道 `{port}` |
| POST | `/api/logs/clear` | 清空日志缓冲 |

出错时统一返回 `{"error": "中文说明"}` 与 4xx 状态码。

## 目录结构

```
webui/
  server.py            HTTP 服务与路由（标准库 http.server）
  cfmanager.py         cloudflared 管理：证书、隧道、映射、进程、日志
  install.sh           Debian/Ubuntu 一键安装（含 systemd 单元）
  static/index.html    单页控制台
  static/app.js        状态轮询与交互
  static/style.css     设计令牌、深浅色主题与响应式布局
```

## 与桌面端的差异

- 授权证书、隧道凭证与 ingress 配置都在**服务器本机**，与桌面端各自独立。
- 无头服务器上 `cloudflared tunnel login` 不会自动开浏览器：面板会轮询出授权链接并自动在
  你的浏览器里打开，也可以点「复制链接」拿到任意设备上完成授权。点面板的「取消」会一并
  结束服务器上的授权进程。
- cloudflared 子进程的 `HOME` 指向数据目录下的 `home/`。服务账号（如 `kelierandes`）常常没有
  可写家目录，cloudflared 启动时会 `mkdir $HOME/.cloudflared`，失败就直接退出、连授权链接都
  不打印——这是「点登录没反应」的常见原因。
- 授权完成后证书落在 `home/.cloudflared/cert.pem`（`tunnel login` 不认 `--origincert`），
  面板会自动接管到数据目录根部的 `cert.pem` 并在日志里记一行「已接收 Cloudflare 授权证书」；
  点「退出登录」会同时清掉这两份，避免被重新接管。
- 删除隧道同样不会自动删除 DNS 记录，需要到 Cloudflare 控制台清理。

## 云端同步与凭证恢复

`cloudflared tunnel token --credentials-file <path> <tunnel>` 会把云端已有隧道的凭证写回本机，
因此「同步云端」可以做三件事：导入本地没有的隧道、补齐丢失的凭证、把云端已删除的隧道标记出来
（只标记不删除）。启动隧道时若发现凭证缺失，也会先自动取回一次。

## 测试

```bash
python3 webui/tests/test_sync.py   # 用假 cloudflared 验证导入与凭证取回
```
