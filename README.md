# Cloudflare Tunnel Manager

一套 Cloudflare Tunnel 内网穿透管理客户端：Windows 桌面端（Flutter）、Android 端，以及给无头
Linux 服务器用的 Web 面板。把 `cloudflared` 的登录、命名隧道、端口映射、DNS CNAME 与实时日志
整合到可视化界面里。

## 下载

发布包在 [Releases](https://github.com/KelierAndes/Cloudflare-Tunnel-App/releases)：

| 平台 | 文件 |
| --- | --- |
| Windows 10/11 x64 | `CloudflareTunnelManager-1.0.0-win64.zip`（解压即用，内置 cloudflared） |
| Android arm64-v8a | `CloudflareTunnel-1.0.0-arm64-v8a.apk`（主流手机） |
| Android x86_64 | `CloudflareTunnel-1.0.0-x86_64.apk`（模拟器） |
| Android 通用 | `CloudflareTunnel-1.0.0-universal.apk` |
| Linux 服务器 | `cloudflare-tunnel-webui-1.0.0.tar.gz`（解压后 `sudo bash install.sh`） |

## 功能

- **命名隧道**：在应用中创建 / 删除 Cloudflare 命名隧道，凭证保存在本机。
- **云端同步**：重新登录、换机器或清理过数据后，点「同步云端」即可导入云端已有隧道并自动取回凭证，**不需要重建隧道**。
- **域名 + 端口映射**：把托管在 Cloudflare 的域名（可带路径前缀）转发到 `localhost:<端口>`。
- **一键 DNS**：通过 `cloudflared tunnel route dns` 自动创建 CNAME，可选覆盖已有记录。
- **启停控制**：单条隧道启停、全部启停、开机后自动连接。
- **后台运行**：关闭窗口可最小化到系统托盘，隧道继续在线；支持登录系统后静默启动。
- **临时隧道**：无需登录，生成 `*.trycloudflare.com` 随机地址，适合快速验证。
- **实时日志**：按来源聚合 cloudflared 的 stdout / stderr，支持自动滚动、复制、清空。
- **运行时管理**：内置官方 cloudflared 2026.10.3，离线可用；也可一键下载最新版或指定本地路径。
- **主题**：深色 / 浅色 / 跟随系统，原生标题栏同步换色。

## 快速开始

1. 解压发布包，运行 `cf_tunnel_manager.exe`。
2. 点击「立即登录」，在浏览器中选择已托管在 Cloudflare 的域名并完成授权。
3. 打开「隧道」页 →「新建隧道」→ 输入名称。
4. 添加端口映射：填写公网域名与本机端口，勾选「同时创建 DNS CNAME 记录」。
5. 点击「启动」。公网访问 `https://你的域名` 即可到达本机端口。

> 域名必须已托管在 Cloudflare。若域名已有 A / CNAME 记录，需要在添加映射时勾选「覆盖已存在的 DNS 记录」。

### 临时测试

概览页的「临时公网测试」输入本机端口即可生成 `*.trycloudflare.com` 地址，无需账户与域名。隧道地址在停止后立即失效。

## 数据位置

所有证书、隧道凭证、ingress 配置与运行时都保存在：

```
%APPDATA%\com.qodertunnel\cf_tunnel_manager\
```

- `cert.pem`：Cloudflare 授权证书（仅本机）
- `credentials\`：命名隧道凭证
- `configs\`：隧道 ingress 配置
- `bin\cloudflared.exe`：内置运行时副本
- `state.json` / `settings.json`：应用配置

「设置 → 本地数据」可以直接打开该目录。

## 后台运行与开机自启（Windows）

设置页的「后台运行」区块提供两个开关：

| 开关 | 作用 |
| --- | --- |
| 关闭窗口时最小化到托盘 | 点标题栏 ✕ 只隐藏窗口，cloudflared 继续运行；双击托盘图标或再次运行 exe 即可唤回窗口 |
| 开机自动启动应用 | 写入当前用户的启动项，登录后静默启动并留在托盘，不弹出窗口 |

- 托盘图标会显示隧道数量（如 `Cloudflare Tunnel Manager · 1 条隧道运行中`），右键菜单为
  「显示主界面 / 隐藏主界面 / 退出并停止隧道」。
- 想让隧道开机常驻，把「开机自动启动应用」和「启动应用时自动连接隧道」一起打开即可。
- 应用是**单实例**的：已经在后台时再次双击 exe 不会重复启动，只会把窗口唤回前台。
- 开机自启写入的是当前用户的注册表启动项：

  ```
  HKCU\Software\Microsoft\Windows\CurrentVersion\Run
  CloudflareTunnelManager = "…\cf_tunnel_manager.exe" --autostart
  ```

  关闭开关即删除该项。**移动 exe 位置后需要重新打开一次开关**，否则启动项指向旧路径。
- 只有 Windows 版显示该区块；Android 用前台服务保活，Linux 面板用 systemd。

## 注意事项

- **首次运行可能弹出 Windows 防火墙授权。** 这是 cloudflared 在绑定本地网络时触发的系统提示；应用只需要出站连接，不会开放入站端口。按需允许或取消都可以，建议允许「专用网络」。
- **换机器 / 重装 / 删除数据目录后**，点右上角「同步云端」：应用会列出账号下的隧道、导入本地缺失的条目，并用 `cloudflared tunnel token --credentials-file` 取回原隧道凭证。缺少凭证的隧道卡片上会显示「缺少凭证」标记与「从云端取回凭证」按钮；启动时也会自动尝试取回一次。
- **云端已删除的隧道**只会被标记为「云端已删除」，不会自动清理本地记录，避免误删。
- **删除隧道不会自动删除 DNS 记录。** 如需停止解析，请到 Cloudflare 控制台删除对应的 CNAME。
- 退出账户只删除本机 `cert.pem`，不会删除 Cloudflare 上的隧道。
- 同一域名 + 路径不能重复映射；隧道运行中修改映射，需要重启隧道生效。
- 应用使用出站连接访问 Cloudflare 边缘，无需公网 IP，也无需在路由器开放入站端口。
- 更新运行时时请先停止所有隧道，否则 Windows 会锁定正在运行的可执行文件。
- 桌面端面向 Windows 10/11 x64；Linux 服务器走 Web 面板；Android 面向 arm64-v8a / x86_64。

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Windows 10/11 x64 | 完整可用 | 内置 cloudflared，离线可用；已端到端验证 |
| Linux 服务器 | 用 Web 面板管理 | 无桌面的机器推荐 [webui/](webui/README.md)：Python 标准库实现，`bash webui/install.sh` 一键部署，功能与桌面端一致，已在 Debian 12 端到端验证 |
| Linux 桌面 | 工程就绪，需在 Linux 上构建 | `flutter build linux` 不支持跨主机生成，需在原生 Linux/WSL2 里执行 `scripts/build_linux.sh` |
| Android arm64-v8a / x86_64 | 可安装可运行，隧道可直连边缘 | APK 内以 `libcloudflared.so` 打包**自行编译**的 cloudflared（cgo + `CF_DNS_SERVER`，解决 Android 无 `resolv.conf` 导致 DNS 失败的问题）；含前台保活服务与移动端安全区适配，已在 Android 14 真机验证 |

Android 产物位于 `build/app/outputs/flutter-apk/`（通用包与按 ABI 拆分包）与
`build/app/outputs/bundle/release/app-release.aab`。当前 release 使用 Flutter 模板的
debug 签名，正式发布需自行配置 keystore；构建 AAB 需要 Android `cmdline-tools`
（Flutter 会用 `apkanalyzer` 校验符号剥离），只装 APK 时不影响。armeabi-v7a 未内置运行时。

## 从源码构建

要求：Flutter 3.38+、Visual Studio 2022/2026（Desktop development with C++）、Windows 10 SDK。

```powershell
flutter pub get
flutter build windows --release
```

构建前先放置对应平台的运行时（避免把 53 MB 的 Windows 二进制打进 Android 包）：

```powershell
powershell -File scripts\stage_runtime.ps1 -Platform windows   # Windows 构建
powershell -File scripts\stage_runtime.ps1 -Platform none      # Android 构建（占位）
bash ./scripts/stage_runtime.sh linux                          # Linux 桌面构建
```

Android 的 cloudflared 需要单独编译（cgo + `CF_DNS_SERVER` 补丁），产物直接写入
`android/app/src/main/jniLibs/<abi>/libcloudflared.so`：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_android_cloudflared.ps1
```

产物位于 `build\windows\x64\runner\Release\`。

如果项目路径过深导致 MSBuild 报 `FTK1011`（文件跟踪器不支持超长路径），可使用附带的短路径构建脚本：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
```

Android 构建若从 `dl.google.com` 下载依赖时出现 `Tag mismatch!`，本工程已在
`android/settings.gradle.kts` 与 `android/build.gradle.kts` 中加入公共镜像（阿里云）作为优先源。

更多实现细节见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 许可证

本项目以 [MIT](LICENSE) 协议开源。随包分发的 `cloudflared` 及 Flutter 依赖遵循各自的许可证，
详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
