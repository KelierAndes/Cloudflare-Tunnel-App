# 开发说明

## 技术栈

- Flutter 3.47 / Dart 3.13，Windows desktop
- `provider` 管理全局状态
- `path_provider` 定位系统应用数据目录
- `http` 流式下载 cloudflared
- `url_launcher` 打开浏览器 / Cloudflare 控制台
- 原生 runner 增补：任务对象（Job Object）、DWM 标题栏配色、MethodChannel

## 目录

```
lib/
  main.dart / app.dart      入口、主题与生命周期
  models/models.dart        隧道、映射、日志、设置模型
  services/
    local_store.dart        应用数据目录与 JSON 持久化
    cloudflared_service.dart  cloudflared 命令封装、YAML、下载
    window_chrome.dart      Dart -> 原生标题栏通道
  state/app_state.dart      登录、隧道进程、DNS、日志聚合
  theme/app_theme.dart      调色板与 Material 主题
  ui/
    shell.dart              侧栏、页面切换、全局 Toast
    dialogs.dart            登录 / 新建隧道 / 端口映射 / 确认框
    pages/                  概览、隧道、日志、设置
    widgets/common.dart     卡片、状态胶囊、动效等
windows/runner/
  main.cpp                  窗口尺寸、DWM、Job Object
  win32_window.cpp          最小窗口尺寸
  flutter_window.cpp        标题栏 MethodChannel
```

## 数据与进程

- 数据根目录来自 `getApplicationSupportDirectory()`，默认
  `%APPDATA%\com.qodertunnel\cf_tunnel_manager`。
- `cert.pem`、隧道凭证与 `configs/<uuid>.yml` 都由应用管理；`cloudflared` 通过
  `--origincert` / `--config` 使用这些文件，避免污染全局 `~/.cloudflared`。
- 命名隧道进程：
  `cloudflared tunnel --config <config> --origincert <cert> --no-autoupdate run <uuid>`
- 临时隧道进程：
  `cloudflared tunnel --no-autoupdate --url http://localhost:<port>`
- 所有子进程随应用退出：runner 将当前进程加入 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`
  的任务对象，应用崩溃 / 关闭窗口时由系统一并回收 cloudflared。

## 日志

`AppState` 将 cloudflared 输出按行解析：

- 级别：`INF/WRN/ERR/DBG/FTL`
- 连接状态：`Registered tunnel connection`、`Unregistered ...`、`Retrying ...`
- 临时隧道地址：`https://<name>.trycloudflare.com`
- 展示前会移除 cloudflared 自带的时间戳与级别前缀，避免与 UI 重复。

日志更新只递增 `logRevision`，不会触发整页重建。

## 跨平台

运行时按平台解析，三处入口：

- `CloudflaredService.platformTarget()` / `downloadUrl()`：windows / linux / android(→linux) 的
  发布产物名与架构（`Abi.current()`）。
- `CloudflaredService.bundledAssetName`：Windows 读取 `assets/bin/cloudflared.exe`，
  其它平台读取 `assets/bin/cloudflared`；小于 1 MB 视为占位并回退到系统 PATH → 下载。
- `LocalStore.binaryFile`：Windows 为 `cloudflared.exe`，其它平台为 `cloudflared`；
  非 Windows 写入或下载后会执行 `chmod 755`。

`assets/bin/` 在 pubspec 中以目录形式声明，构建前用 `scripts/stage_runtime.ps1|sh`
放置对应平台的二进制；目录不能为空。

平台差异点：

- `AppState.openDataFolder()`：Windows `explorer.exe`、Linux `xdg-open`、macOS `open`；
  Android 不支持，相关按钮通过 `AppState.canOpenDataFolder` 隐藏。
- `WindowChrome`（标题栏配色）与 runner 的 Job Object、`WM_GETMINMAXINFO` 只在 Windows 生效，
  通道调用失败会被静默忽略。
- `_findSystemBinary()` 在 Windows 用 `where`，其它平台用 `which`。

### Android 现状与待办

- 已验证：`flutter build apk --release`（通用 + `--split-per-abi`）成功，安装到真机后
  Activity 正常启动、窗口完成首帧、无 Flutter 异常。
- 依赖解析：`dl.google.com` 在部分网络下返回 `Tag mismatch!`，已在
  `android/settings.gradle.kts`、`android/build.gradle.kts` 中加入阿里云镜像优先源。
- 待办（隧道真正可用所需）：
  1. 以 `android/app/src/main/jniLibs/<abi>/libcloudflared.so` 打包可执行文件
     （Android 10+ 禁止 exec 应用私有目录中的二进制），并加一个返回
     `applicationInfo.nativeLibraryDir` 的 MethodChannel；
  2. 前台服务（如 `flutter_foreground_task`）+ `FOREGROUND_SERVICE` 权限，避免后台被杀；
  3. 手机/头显尺寸下的布局适配（当前为桌面侧栏布局）。
- AAB 的符号剥离校验依赖 Android `cmdline-tools` 里的 `apkanalyzer`；缺少该组件时
  Gradle 仍会产出 `app-release.aab`，但 `flutter build appbundle` 以非 0 退出。

### Linux 现状

- `linux/` 工程与 `scripts/build_linux.sh` 已就绪；Flutter 不支持在 Windows 主机上
  `flutter build linux`（`"build linux" only supported on Linux hosts.`），
  需在原生 Linux 或启用后的 WSL2 中构建，依赖：
  `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`。

## 云端同步与凭证恢复

`AppState.syncAccount()` / `CloudflaredManager.sync_tunnels()` 会：

1. `cloudflared tunnel --origincert <cert> list --output json` 取云端隧道（`parseRemoteTunnels`
   对 `id/UUID`、`name/Name`、`created_at/createdAt` 做兼容解析）；
2. 本地没有的条目直接导入，凭证路径用 `credentialsFileName(name, id)`（名称 + ID 前 8 位）
   避免云端重名隧道互相覆盖；
3. 凭证文件不存在的，用 `cloudflared tunnel token --credentials-file <path> <id>` 从云端取回；
4. 云端已删除的本地隧道记入 `remoteMissing`，只标记不删除。

`startTunnel()` 在凭证缺失时会先自动取回一次，失败才提示用户；UI 上对应「缺少凭证」标记、
「从云端取回凭证」按钮与概览页的批量恢复提示。

回归测试：`test/cloud_sync_test.dart`（Dart 解析与命名）与 `webui/tests/test_sync.py`
（用 `webui/tests/fake_cloudflared.sh` 模拟云端，跑完整导入/恢复流程）。

## WebUI 无头授权

`CloudflaredManager.start_login()` 起 `cloudflared tunnel login` 后由 reader 线程抓
`LOGIN_URL`；面板 `startLoginFlow()` 每 1.2s 轮询 `/api/login/check`
（`{loggedIn, loggingIn, loginUrl, error}`），拿到链接后填进弹窗并 `window.open`
到操作者自己的浏览器——服务器上没有浏览器可用。关闭弹窗会调 `/api/login/cancel`。

两个坑：

- **`HOME` 必须可写**：cloudflared 启动时会 `mkdir $HOME/.cloudflared`，服务账号
  （`User=kelierandes`，家目录不存在且 `ProtectHome=read-only`）会直接以
  `mkdir ...: no such file or directory` 退出，连授权链接都不打印。所有子进程都经
  `_child_env()` 把 `HOME` 指到 `<data>/home`。
- **失败要能看见**：进程退出且没拿到链接时，把 stderr 最后一行写进 `loginError`，
  面板显示「授权流程启动失败：<原因>」，否则用户只会看到一个永远在转的对话框。
- **证书路径**：`cloudflared tunnel login --help` 里没有 `--origincert`（只认
  `--loginURL/--callbackURL`），授权完成后证书固定写到 `$HOME/.cloudflared/cert.pem`。
  `_adopt_login_cert()` 会在登录进程结束时（`force=True`，覆盖旧账号）、以及每次
  `login_status()` 与启动加载时（仅当 `cert_path` 缺失）把它接管到 `cert_path`；
  `logout()` 必须同时删除两份，否则下次会被重新接管成「退不出去」。

## Windows 后台运行与开机自启

托盘、窗口拦截与启动项全部在原生 runner 里实现，没有引入额外插件依赖。

- `windows/runner/flutter_window.cpp`
  - `Shell_NotifyIconW` 注册托盘图标（`WM_APP+1` 回调）；左键唤回窗口，右键
    `TrackPopupMenu(TPM_RETURNCMD)`，按 `hidden_in_tray_` 灰化「显示 / 隐藏」；
    退出项通过 `InvokeMethod("requestQuit")` 回到 Dart 停隧道，并挂一个 5 秒
    `SetTimer` 兜底，避免 isolate 卡死时窗口关不掉。
  - `WM_CLOSE` 在交给 Flutter 之前拦截：`close_to_tray_` 为真时只 `SW_HIDE`；
    `WM_QUERYENDSESSION` 会置 `force_quit_`，注销/关机时正常退出。
  - `cf_tunnel/window` 通道新增 `hideToTray / quit / setCloseToTray /
    setTooltip / setAutoStart / isAutoStartEnabled`；`setAutoStart` 读写
    `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 的 `CloudflareTunnelManager`
    值（内容为 `"<exe>" --autostart`），`isAutoStartEnabled` 会校验值里是否包含当前
    exe 路径，所以移动目录后设置页会显示为未开启。
  - 菜单文案是中文宽字符串，runner 需要 `/utf-8` 编译选项，否则 MSVC 会按本地代码页
    解释源码里的 UTF-8 字面量。
- `windows/runner/main.cpp`：命令行含 `--autostart` / `--minimized` 时首帧不 `Show()`；
  release 构建用命名互斥体做单实例，二次启动只向已有窗口投递
  `cf_window::kShowFromSecondInstance` 后退出（debug 不启用，方便 `flutter run`）。
- Dart 侧：`WindowChrome`（`lib/services/window_chrome.dart`）封装通道调用，
  `AppState._bindWindowChrome()` 在 `init()` 里绑定退出回调、下发 `minimizeToTray`、
  并调用 `_reconcileBootStart()` 用系统真实状态纠正 `settings.autoStartOnBoot`；
  `notifyListeners()` 里按在线隧道数变化刷新托盘 tooltip。
- cloudflared 子进程仍由 Job Object（`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`）托管，
  因此托盘「退出」、`Stop-Process`、崩溃三种路径都不会留下孤儿进程。

## Android 运行时

Android 上没有 `/etc/resolv.conf`，也无法运行 ptrace 类工具（proot 在 App 沙箱里连
`/system/bin/echo` 都 exec 不了），所以随包使用的不是官方 Linux 二进制，而是用
NDK 自编译的版本：

重新生成（需要 Go 1.27+ 与 NDK；脚本会浅克隆 2026.10.3 源码并打补丁）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_android_cloudflared.ps1
```

等价的直接命令：

```bash
GOOS=android GOARCH=arm64 CGO_ENABLED=1 CC=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android21-clang go build -trimpath -ldflags "-s -w -X main.Version=2026.10.3" -o libcloudflared.so ./cmd/cloudflared
```

补丁文件：`android/patches/cloudflared-cf_dns_server.patch`。

- `CGO_ENABLED=1`：A/AAAA 查询走 bionic 的 `getaddrinfo`，TLS 用
  `/system/etc/security/cacerts`，都不需要额外挂载。
- 补丁 `cmd/cloudflared/main.go: useEnvDNSServer()`：bionic 不支持 SRV，边缘发现
  （`_v2-origntunneld._tcp.argotunnel.com`）必须走 Go 自己的解析器，因此允许用
  `CF_DNS_SERVER=<dns>:53` 指定解析服务器；Dart 侧从 `ConnectivityManager` 取系统 DNS
  后注入（`CfLauncher.wrap`）。
- `login` 仍把证书写到 `$HOME/.cloudflared`，所以子进程 `HOME` 指向数据目录，
  并在 `AppState._adoptLoginCert()` 里接管到 `cert.pem`。
- AGP 会 strip `jniLibs/*.so`，静态可执行文件会被改坏（proot 从 1.4 MB 变成 291 KB），
  `android/app/build.gradle.kts` 已对 `libcloudflared.so` 设置 `keepDebugSymbols`。
- 产物：`android/app/src/main/jniLibs/<abi>/libcloudflared.so`（仓库内已提交）。

## 构建约束

- 仓库如果位于超长路径下，MSBuild 的 FileTracker 可能报 `FTK1011`。使用
  `scripts/build_windows.ps1` 将父目录映射到短盘符后再构建。
- `windows/runner/CMakeLists.txt` 链接 `dwmapi.lib`、`shell32.lib`（托盘）与
  `advapi32.lib`（启动项）；新增原生调用时注意保持。
- cloudflared 以 asset 形式打进 `data/flutter_assets/assets/bin/cloudflared.exe`，
  首次启动复制到应用数据目录；更新版本可走设置页下载。

## 验证

```powershell
flutter analyze
flutter test
```

测试覆盖域名 / 端口 / 隧道名校验与映射序列化。临时隧道可通过本地 HTTP 服务 +
公网地址做端到端验证：

```powershell
python -m http.server 8765
# 在应用概览页启动临时隧道，访问生成的 trycloudflare.com 地址
```

托盘部分的可复现验证方式（Win11 的托盘图标默认收在溢出区，Computer Use 点不到）：

1. 用 UIA 点 `Shell_TrayWnd` 里名为「显示隐藏的图标」的按钮，再到顶层窗口
   `TopLevelWindowForOverflowXamlIsland` 里按 Name 找图标——Name 就是 tooltip，
   可以直接断言 `Cloudflare Tunnel Manager · N 条隧道运行中`。
2. 图标位置每次打开 flyout 都可能变化，必须在同一次脚本里「打开 → 取 rect → 右键」，
   跨进程复用旧 rect 会点空；右键后用 `GetWindowThreadProcessId` 比对 `#32768` 窗口的
   宿主 PID 才能确认菜单是自己的应用。
3. 菜单展开期间 UIA 读不到菜单项（runner 线程在模态循环里），改用
   `Graphics.CopyFromScreen` 截图确认文案，再按 `menu_rect` 折算条目中心坐标点击。
4. 隐藏 / 唤回的效果用 `FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", "Cloudflare Tunnel")`
   + `IsWindowVisible` 断言；开机静默启动用 `--autostart` 拉起后同样断言
   `visible=False` 且公网地址仍可访问。

