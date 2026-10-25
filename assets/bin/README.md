# 内置运行时目录

构建时该目录里放置对应平台的 cloudflared 可执行文件：

| 平台 | 资源名 | 说明 |
| --- | --- | --- |
| Windows | `cloudflared.exe` | 随应用打包，首次启动释放到数据目录 |
| Linux / Android | `cloudflared` | 可选；未提供时应用会在设置页下载官方运行时 |

该目录不能为空，否则 `flutter build` 会报缺少资源。
用 `scripts/stage_runtime.ps1`（Windows）或 `scripts/stage_runtime.sh`（Linux/macOS）
在构建前放置正确的文件。

注意：Android 上把可执行文件放在应用私有目录里无法直接运行（系统 noexec），
需要通过 `jniLibs/<abi>/libcloudflared.so` 打包。当前 Android 版本尚未启用该方案。
