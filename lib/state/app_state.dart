import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/cf_launcher.dart';
import '../services/cloudflared_service.dart';
import '../services/local_store.dart';
import '../services/platform_bridge.dart';
import '../services/window_chrome.dart';

class UiMessage {
  UiMessage(this.text, {this.error = false});

  final String text;
  final bool error;
}

class AppState extends ChangeNotifier {
  final LocalStore store = LocalStore();
  late final CfLauncher launcher = CfLauncher(store);
  late final CloudflaredService cf = CloudflaredService(store, launcher);

  AppSettings settings = AppSettings();
  List<Tunnel> tunnels = <Tunnel>[];
  final Map<String, TunnelRuntime> runtimes = <String, TunnelRuntime>{};
  final Map<String, Process> _processes = <String, Process>{};
  final QuickTunnelRuntime quick = QuickTunnelRuntime();
  Process? _quickProcess;

  final List<LogEntry> systemLogs = <LogEntry>[];
  final Set<String> routingEndpoints = <String>{};
  final Set<String> pendingRestart = <String>{};

  /// 本机有记录、但云端已不存在的隧道。
  final Set<String> remoteMissing = <String>{};

  /// 凭证文件缺失、需要从云端取回的隧道。
  final Set<String> missingCredentials = <String>{};

  bool ready = false;
  bool preparingRuntime = false;
  bool downloading = false;
  double downloadProgress = 0;
  String? binaryPath;
  String? binaryVersion;
  String? binaryError;

  bool loggedIn = false;
  bool loggingIn = false;
  String? loginUrl;
  bool syncing = false;
  bool creating = false;
  bool deleting = false;
  String? lastSyncError;

  final StreamController<UiMessage> _messages =
      StreamController<UiMessage>.broadcast();
  Stream<UiMessage> get messages => _messages.stream;

  /// 只标记日志变化，避免整页在每行日志到达时重建。
  final ValueNotifier<int> logRevision = ValueNotifier<int>(0);

  Timer? _loginWatch;
  Process? _loginProcess;
  final List<String> _loginOutput = <String>[];
  bool _finishingLogin = false;
  Timer? _logNotifyTimer;

  int get activeTunnelCount =>
      tunnels.where((t) => runtimes[t.id]?.phase.isLive ?? false).length;

  int get totalConnectionCount {
    var count = quick.connectionCount;
    for (final runtime in runtimes.values) {
      count += runtime.connectionCount;
    }
    return count;
  }

  int get endpointCount =>
      tunnels.fold(0, (sum, tunnel) => sum + tunnel.endpoints.length);

  bool get anyTunnelRunning =>
      quick.phase.isLive ||
      _processes.isNotEmpty ||
      tunnels.any((t) => runtimes[t.id]?.phase.isLive ?? false);

  bool get isBinaryReady => binaryPath != null;

  List<LogEntry> get allLogs {
    final list = <LogEntry>[...systemLogs, ...quick.logs];
    for (final tunnel in tunnels) {
      list.addAll(runtimes[tunnel.id]?.logs ?? const []);
    }
    list.sort((a, b) => a.time.compareTo(b.time));
    if (list.length > 1500) {
      return list.sublist(list.length - 1500);
    }
    return list;
  }

  List<String> get logSources => [
    '全部',
    '系统',
    '临时隧道',
    for (final tunnel in tunnels) tunnel.name,
  ];

  Future<void> init() async {
    await store.init();
    await _adoptLoginCert();
    settings = store.loadSettings();
    _bindWindowChrome();
    tunnels = store.loadTunnels();
    for (final tunnel in tunnels) {
      runtimes[tunnel.id] = TunnelRuntime();
    }
    _trimIdleLogs();
    await _refreshCredentialFlags();
    loggedIn = _hasCert();
    notifyListeners();

    preparingRuntime = true;
    notifyListeners();
    try {
      await _ensureRuntime();
    } catch (error) {
      binaryError = '运行时准备失败：$error';
      debugPrint(binaryError);
    }
    preparingRuntime = false;
    _devLog(
      'runtime=${binaryPath ?? 'none'} version=${binaryVersion ?? 'none'} '
      'platform=${Platform.operatingSystem} dataDir=${store.root.path}',
    );
    notifyListeners();

    _sys('应用已启动，数据目录：${store.root.path}');
    if (binaryVersion != null) {
      _sys('cloudflared 运行时就绪 · v$binaryVersion');
    }
    if (loggedIn) {
      _sys('检测到 Cloudflare 授权证书');
      unawaited(syncAccount(silent: true));
      if (settings.autoStartTunnels) {
        for (final tunnel in tunnels.where((t) => t.endpoints.isNotEmpty)) {
          unawaited(startTunnel(tunnel.id));
        }
      }
    }
    ready = true;
    notifyListeners();
  }

  bool _hasCert() {
    try {
      final file = store.certFile;
      return file.existsSync() && file.lengthSync() > 100;
    } catch (_) {
      return false;
    }
  }

  /// Windows 托盘：关闭按钮隐藏窗口，托盘「退出」先收掉隧道进程再退进程。
  void _bindWindowChrome() {
    if (!WindowChrome.supportsBackground) return;
    WindowChrome.onQuitRequest(() async {
      _sys('收到托盘退出请求，正在停止所有隧道…');
      await shutdown();
      await WindowChrome.quit();
    });
    unawaited(WindowChrome.setCloseToTray(settings.minimizeToTray));
    unawaited(_reconcileBootStart());
    _refreshTrayTooltip();
  }

  /// 启动项可能被安全软件或用户直接改动，以系统里的真实状态为准。
  Future<void> _reconcileBootStart() async {
    final actual = await WindowChrome.autoStartEnabled();
    if (actual == settings.autoStartOnBoot) return;
    settings.autoStartOnBoot = actual;
    await store.saveSettings(settings);
    _sys('检测到系统启动项已${actual ? '存在' : '被移除'}，设置已同步');
    notifyListeners();
  }

  String get _trayTooltip {
    final count = activeTunnelCount + (quick.phase.isLive ? 1 : 0);
    if (count == 0) return 'Cloudflare Tunnel Manager';
    return 'Cloudflare Tunnel Manager · $count 条隧道运行中';
  }

  int _trayTooltipSignature = -1;

  void _refreshTrayTooltip() {
    if (!WindowChrome.supportsBackground) return;
    final count = activeTunnelCount + (quick.phase.isLive ? 1 : 0);
    if (count == _trayTooltipSignature) return;
    _trayTooltipSignature = count;
    unawaited(WindowChrome.setTooltip(_trayTooltip));
  }

  Future<void> _ensureRuntime() async {
    await store.ensureDirs();
    final custom = settings.binaryPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      final file = File(custom);
      if (await file.exists()) {
        binaryPath = file.path;
      } else {
        binaryError = '自定义 cloudflared 路径不存在，已回退到内置运行时';
        settings.binaryPath = null;
        await store.saveSettings(settings);
      }
    }
    if (binaryPath == null) {
      await _usePackagedAndroidRuntime();
    }
    if (binaryPath == null) {
      await _extractBundledRuntime();
    }
    if (binaryPath == null) {
      final system = await _findSystemBinary();
      if (system != null) {
        binaryPath = system;
        _sys('未找到内置运行时，使用系统 cloudflared：$system');
      }
    }
    if (binaryPath == null) {
      binaryError = Platform.isAndroid
          ? '未找到可用的 cloudflared（APK 未打包 arm64 运行时）'
          : '未找到 cloudflared 运行时';
      return;
    }
    if (Platform.isAndroid) {
      await _prepareAndroidSandbox();
    }
    binaryVersion = await cf.version(binaryPath!);
    if (binaryVersion == null) {
      binaryError = '内置 cloudflared 无法运行，请尝试重新下载';
      binaryPath = null;
    }
  }

  /// Android：执行 jniLibs 解压出的 libcloudflared.so。
  Future<void> _usePackagedAndroidRuntime() async {
    if (!Platform.isAndroid) return;
    final dir = await PlatformBridge.nativeLibraryDir();
    if (dir == null || dir.isEmpty) return;
    final candidate = File('$dir${Platform.pathSeparator}libcloudflared.so');
    if (await candidate.exists()) {
      binaryPath = candidate.path;
      _sys('使用 APK 内置的 cloudflared 运行时');
    }
  }

  /// Android：cloudflared 读不到 /etc/resolv.conf，运行时把系统 DNS 传下去。
  Future<void> _prepareAndroidSandbox() async {
    if (!Platform.isAndroid) return;
    final servers = await PlatformBridge.dnsServers();
    _sys(
      'Android DNS：${servers.isEmpty ? '未从系统获取到，将使用 cloudflared 默认值' : servers.join(', ')}',
    );
  }

  /// `cloudflared tunnel login` 不认 --origincert，证书固定写到 $HOME/.cloudflared。
  Future<void> _adoptLoginCert() async {
    try {
      if (await store.certFile.exists()) return;
      final fallback = store.defaultCertFile;
      if (!await fallback.exists() || await fallback.length() < 100) return;
      await fallback.copy(store.certFile.path);
      _sys('已接收 Cloudflare 授权证书');
    } catch (error) {
      debugPrint('接管授权证书失败: $error');
    }
  }

  Future<void> _extractBundledRuntime() async {
    final target = store.binaryFile;
    try {
      final needsWrite =
          !await target.exists() || await target.length() < 1024 * 1024;
      if (needsWrite) {
        final data = await rootBundle.load(CloudflaredService.bundledAssetName);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.length < 1024 * 1024) {
          // 构建时只放了占位文件（例如 Android / Linux 未打包运行时）。
          return;
        }
        await target.writeAsBytes(bytes, flush: true);
        await _markExecutable(target.path);
      }
      binaryPath = target.path;
    } catch (error) {
      debugPrint('未找到可用的内置运行时: $error');
    }
  }

  Future<void> _markExecutable(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['755', path]);
    } catch (error) {
      debugPrint('设置可执行权限失败: $error');
    }
  }

  Future<String?> _findSystemBinary() async {
    final finder = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(
        finder,
        ['cloudflared'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        final first = '${result.stdout}'.split('\n').first.trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------- 设置

  Future<void> setThemeMode(String mode) async {
    settings.themeMode = mode;
    await store.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setAutoStart(bool value) async {
    settings.autoStartTunnels = value;
    await store.saveSettings(settings);
    notifyListeners();
  }

  /// 仅 Windows 有托盘与启动项，其他平台该区块整体隐藏。
  bool get supportsBackground => WindowChrome.supportsBackground;

  Future<void> setMinimizeToTray(bool value) async {
    settings.minimizeToTray = value;
    await store.saveSettings(settings);
    await WindowChrome.setCloseToTray(value);
    _sys(value ? '关闭窗口后将留在系统托盘继续运行' : '关闭窗口将直接退出应用');
    notifyListeners();
  }

  Future<void> setBootStart(bool value) async {
    final error = await WindowChrome.setAutoStart(value);
    if (error != null) {
      _sys('开机自启设置失败：$error', level: LogLevel.error);
      _toast(error, error: true);
      notifyListeners();
      return;
    }
    settings.autoStartOnBoot = value;
    await store.saveSettings(settings);
    _sys(value ? '已写入系统启动项：登录后可静默运行，是否自动连接隧道由「自动连接隧道」决定' : '已移除系统启动项');
    _toast(value ? '已开启开机自启' : '已关闭开机自启');
    notifyListeners();
  }

  Future<void> hideToTray() async {
    await WindowChrome.hideToTray();
  }

  Future<void> setQuickPort(int port) async {
    settings.quickPort = port;
    await store.saveSettings(settings);
  }

  Future<bool> setCustomBinaryPath(String path) async {
    final value = path.trim();
    if (anyTunnelRunning) {
      _toast('请先停止所有隧道再更换运行时', error: true);
      return false;
    }
    if (value.isEmpty) {
      settings.binaryPath = null;
      binaryPath = null;
      binaryVersion = null;
      binaryError = null;
      await _ensureRuntime();
      await store.saveSettings(settings);
      notifyListeners();
      if (binaryPath != null) {
        _toast('已恢复内置运行时');
        return true;
      }
      _toast(binaryError ?? '内置运行时不可用', error: true);
      return false;
    }
    final file = File(value);
    if (!await file.exists()) {
      _toast('文件不存在：$value', error: true);
      return false;
    }
    final version = await cf.version(value);
    if (version == null) {
      _toast('该文件不是可用的 cloudflared', error: true);
      return false;
    }
    settings.binaryPath = value;
    binaryPath = value;
    binaryVersion = version;
    binaryError = null;
    await store.saveSettings(settings);
    _sys('已切换 cloudflared 运行时：$value');
    notifyListeners();
    _toast('运行时已切换 · v$version');
    return true;
  }

  Future<void> refreshRuntimeVersion() async {
    if (binaryPath == null) {
      await _ensureRuntime();
    } else {
      binaryVersion = await cf.version(binaryPath!);
    }
    notifyListeners();
    if (binaryVersion == null) {
      _toast('无法运行 cloudflared，请重新下载运行时', error: true);
    } else {
      _toast('运行时正常 · v$binaryVersion');
    }
  }

  Future<void> downloadRuntime() async {
    if (downloading) return;
    if (anyTunnelRunning) {
      _toast('请先停止所有隧道再更新运行时', error: true);
      return;
    }
    downloading = true;
    downloadProgress = 0;
    binaryError = null;
    notifyListeners();
    _sys('开始下载 cloudflared 官方运行时…');
    try {
      await store.ensureDirs();
      await cf.downloadRuntime(
        store.binaryFile,
        onProgress: (progress) {
          downloadProgress = progress;
          notifyListeners();
        },
      );
      settings.binaryPath = null;
      await store.saveSettings(settings);
      binaryPath = store.binaryFile.path;
      binaryVersion = await cf.version(binaryPath!);
      if (binaryVersion == null) {
        throw Exception('下载的文件无法运行');
      }
      _sys('cloudflared 已更新至 v$binaryVersion');
      _toast('运行时已更新 · v$binaryVersion');
    } catch (error) {
      binaryError = '$error';
      _sys('运行时下载失败：$error', level: LogLevel.error);
      _toast('下载失败：$error', error: true);
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- 登录

  Future<void> startLogin() async {
    if (loggingIn) return;
    if (binaryPath == null) {
      _toast('cloudflared 运行时尚未就绪', error: true);
      return;
    }
    await store.ensureDirs();
    loggingIn = true;
    loginUrl = null;
    _loginOutput.clear();
    notifyListeners();
    _sys('正在启动 Cloudflare 授权流程…');
    try {
      final command = await launcher.wrap(binaryPath!, [
        'tunnel',
        '--origincert',
        store.certFile.path,
        'login',
      ]);
      final process = await Process.start(
        command.executable,
        command.args,
        environment: command.environment,
      );
      _loginProcess = process;
      _wire(process.stdout, (line) => _handleLoginLine(line));
      _wire(process.stderr, (line) => _handleLoginLine(line));
      unawaited(
        process.exitCode.then((code) async {
          if (_loginProcess == process) {
            _loginProcess = null;
          }
          if (loggingIn) {
            await _finishLogin(exitCode: code);
          }
        }),
      );
      _loginWatch?.cancel();
      _loginWatch = Timer.periodic(const Duration(milliseconds: 800), (
        _,
      ) async {
        if (!loggingIn) return;
        if (!_hasCert()) await _adoptLoginCert();
        if (loggingIn && _hasCert()) {
          unawaited(_finishLogin());
        }
      });
    } catch (error) {
      loggingIn = false;
      notifyListeners();
      _sys('无法启动登录进程：$error', level: LogLevel.error);
      _toast('无法启动登录进程：$error', error: true);
    }
  }

  void _handleLoginLine(String line) {
    if (line.trim().isEmpty) return;
    _loginOutput.add(line);
    if (_loginOutput.length > 40) _loginOutput.removeAt(0);
    final match = RegExp(r'https://[^\s]+argotunnel[^\s]*').firstMatch(line);
    if (match != null) {
      var url = match.group(0)!;
      url = url.replaceAll(RegExp(r'["\x27]+$'), '');
      if (loginUrl != url) {
        loginUrl = url;
        notifyListeners();
      }
    }
    _sys(line);
  }

  Future<void> _finishLogin({int? exitCode}) async {
    if (_finishingLogin) return;
    _finishingLogin = true;
    try {
      await _adoptLoginCert();
      _loginWatch?.cancel();
      _loginWatch = null;
      if (_hasCert()) {
        loggedIn = true;
        loggingIn = false;
        _sys('Cloudflare 账户授权成功', level: LogLevel.info);
        _toast('Cloudflare 账户已连接');
        await syncAccount(silent: true);
      } else if (exitCode != null) {
        loggingIn = false;
        final detail = _loginOutput.isEmpty
            ? '授权未完成'
            : CloudflaredService.friendlyError(
                _loginOutput.join('\n'),
                fallback: '授权未完成',
              );
        _sys('登录未完成：$detail', level: LogLevel.error);
        _toast('登录未完成：$detail', error: true);
      }
    } finally {
      _finishingLogin = false;
      notifyListeners();
    }
  }

  Future<void> cancelLogin() async {
    _loginWatch?.cancel();
    _loginWatch = null;
    final process = _loginProcess;
    _loginProcess = null;
    loggingIn = false;
    loginUrl = null;
    if (process != null) {
      process.kill();
    }
    _sys('已取消 Cloudflare 授权');
    notifyListeners();
  }

  Future<void> logout() async {
    await stopAllTunnels();
    await store.deleteCert();
    loggedIn = false;
    notifyListeners();
    _sys('已退出 Cloudflare 账户');
    _toast('已退出 Cloudflare 账户');
  }

  Future<void> openLoginUrl() async {
    final url = loginUrl;
    if (url == null) return;
    await _open(url);
  }

  // ---------------------------------------------------------------- 隧道管理

  Future<void> syncAccount({bool silent = false}) async {
    if (syncing) return;
    if (binaryPath == null) return;
    if (!_hasCert()) {
      loggedIn = false;
      if (!silent) _toast('请先登录 Cloudflare 账户', error: true);
      notifyListeners();
      return;
    }
    loggedIn = true;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    var imported = 0;
    var repaired = 0;
    try {
      final result = await cf.listTunnels(binaryPath!, store.certFile.path);
      if (!result.ok) {
        throw Exception(
          CloudflaredService.friendlyError(
            result.combined,
            fallback: '无法读取云端隧道列表',
          ),
        );
      }
      final remote = parseRemoteTunnels(result.combined);
      final remoteIds = <String>{};
      for (final item in remote) {
        remoteIds.add(item.id);
        var local = _tunnelById(item.id);
        if (local == null) {
          local = Tunnel(
            id: item.id,
            name: item.name,
            credentialsPath: store.credentialsPathFor(item.name, item.id),
            createdAt: item.createdAt,
          );
          tunnels.add(local);
          runtimes[item.id] = TunnelRuntime();
          imported++;
          _sys('从云端导入隧道「${item.name}」');
        }
        if (!await File(local.credentialsPath).exists()) {
          if (await _fetchCredentials(local)) repaired++;
        }
      }
      remoteMissing
        ..clear()
        ..addAll(
          tunnels.where((t) => !remoteIds.contains(t.id)).map((t) => t.id),
        );
      await _refreshCredentialFlags();
      await _persist();
      final summary = remote.isEmpty
          ? '云端还没有隧道'
          : '云端 ${remote.length} 条隧道'
                '${imported > 0 ? '，导入 $imported 条' : ''}'
                '${repaired > 0 ? '，恢复凭证 $repaired 条' : ''}';
      _sys('账户同步完成：$summary');
      if (!silent) _toast(summary);
    } catch (error) {
      final message = '$error'.replaceFirst('Exception: ', '');
      lastSyncError = message;
      if (message.toLowerCase().contains('cert') ||
          message.toLowerCase().contains('login')) {
        loggedIn = false;
      }
      if (!silent) {
        _toast(message, error: true);
      }
      _sys('账户同步失败：$message', level: LogLevel.warn);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<bool> _fetchCredentials(Tunnel tunnel) async {
    final binary = binaryPath;
    if (binary == null || !_hasCert()) return false;
    final file = File(tunnel.credentialsPath);
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final result = await cf.fetchCredentials(
        binary,
        store.certFile.path,
        tunnel.id,
        tunnel.credentialsPath,
      );
      if (!result.ok || !await file.exists()) {
        _sys(
          '取回「${tunnel.name}」凭证失败：'
          '${CloudflaredService.friendlyError(result.combined, fallback: '云端取回凭证失败')}',
          level: LogLevel.error,
        );
        return false;
      }
      _sys('已取回隧道「${tunnel.name}」的凭证');
      return true;
    } catch (error) {
      _sys('取回凭证异常：$error', level: LogLevel.error);
      return false;
    }
  }

  /// 手动恢复某条隧道的凭证（用于换机、重装或删除数据后）。
  Future<bool> repairCredentials(String tunnelId) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return false;
    if (binaryPath == null || !loggedIn) {
      _toast('请先登录 Cloudflare 账户', error: true);
      return false;
    }
    final ok = await _fetchCredentials(tunnel);
    await _refreshCredentialFlags();
    notifyListeners();
    _toast(ok ? '凭证已恢复' : '无法从云端恢复该隧道的凭证', error: !ok);
    return ok;
  }

  Future<void> _refreshCredentialFlags() async {
    missingCredentials.clear();
    for (final tunnel in tunnels) {
      if (!await File(tunnel.credentialsPath).exists()) {
        missingCredentials.add(tunnel.id);
      }
    }
  }

  Future<Tunnel?> createTunnel(String name) async {
    if (creating) return null;
    if (binaryPath == null) {
      _toast('运行时尚未就绪', error: true);
      return null;
    }
    if (!loggedIn) {
      _toast('请先登录 Cloudflare 账户', error: true);
      return null;
    }
    creating = true;
    notifyListeners();
    final tempCredentials = store.credentialsPathFor(name, 'tmp${newId()}');
    try {
      await store.ensureDirs();
      final credFile = File(tempCredentials);
      if (await credFile.exists()) await credFile.delete();
      final result = await cf.createTunnel(
        binaryPath!,
        store.certFile.path,
        name,
        tempCredentials,
      );
      if (!result.ok) {
        throw Exception(
          CloudflaredService.friendlyError(result.combined, fallback: '创建隧道失败'),
        );
      }
      String? id;
      if (await credFile.exists()) {
        try {
          final decoded = jsonDecode(await credFile.readAsString());
          id = decoded is Map ? decoded['TunnelID'] as String? : null;
        } catch (_) {}
      }
      id ??= RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      ).firstMatch(result.combined)?.group(0);
      if (id == null) {
        throw Exception('无法解析隧道 ID，请检查 cloudflared 输出');
      }
      // 凭证文件按「名称-ID」归档，避免云端重名隧道互相覆盖。
      final credentialsPath = store.credentialsPathFor(name, id);
      if (await credFile.exists()) {
        await credFile.rename(credentialsPath);
      }
      final tunnel = Tunnel(
        id: id,
        name: name,
        credentialsPath: credentialsPath,
      );
      tunnels.add(tunnel);
      runtimes[id] = TunnelRuntime();
      await _refreshCredentialFlags();
      await _persist();
      _sys('已创建隧道「$name」($id)');
      _toast('隧道「$name」已创建');
      return tunnel;
    } catch (error) {
      final message = '$error'.replaceFirst('Exception: ', '');
      _sys('创建隧道失败：$message', level: LogLevel.error);
      _toast(message, error: true);
      return null;
    } finally {
      creating = false;
      notifyListeners();
    }
  }

  Future<void> deleteTunnel(String tunnelId) async {
    if (deleting) return;
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return;
    deleting = true;
    notifyListeners();
    try {
      await stopTunnel(tunnelId);
      if (binaryPath != null && _hasCert()) {
        await cf.cleanupTunnel(binaryPath!, store.certFile.path, tunnelId);
        final result = await cf.deleteTunnel(
          binaryPath!,
          store.certFile.path,
          tunnelId,
        );
        if (!result.ok) {
          throw Exception(
            CloudflaredService.friendlyError(
              result.combined,
              fallback: '云端删除失败',
            ),
          );
        }
      }
      tunnels.removeWhere((t) => t.id == tunnelId);
      runtimes.remove(tunnelId);
      pendingRestart.remove(tunnelId);
      remoteMissing.remove(tunnelId);
      missingCredentials.remove(tunnelId);
      final config = File(store.configPathFor(tunnelId));
      if (await config.exists()) await config.delete();
      final cred = File(tunnel.credentialsPath);
      if (await cred.exists()) await cred.delete();
      await _persist();
      _sys('已删除隧道「${tunnel.name}」');
      _toast('隧道已删除（域名 DNS 记录请按需在 Cloudflare 面板清理）');
    } catch (error) {
      final message = '$error'.replaceFirst('Exception: ', '');
      _toast(message, error: true);
      _sys('删除隧道失败：$message', level: LogLevel.error);
    } finally {
      deleting = false;
      notifyListeners();
    }
  }

  Future<bool> addEndpoint(
    String tunnelId,
    TunnelEndpoint endpoint, {
    bool routeDns = false,
    bool overwriteDns = false,
  }) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return false;
    final duplicate = tunnel.endpoints.any(
      (e) =>
          e.hostname.toLowerCase() == endpoint.hostname.toLowerCase() &&
          (e.path ?? '') == (endpoint.path ?? ''),
    );
    if (duplicate) {
      _toast('该域名与路径的映射已存在', error: true);
      return false;
    }
    tunnel.endpoints.add(endpoint);
    if (runtimes[tunnelId]?.phase.isLive ?? false) {
      pendingRestart.add(tunnelId);
    }
    await _persist();
    notifyListeners();
    _sys('已为「${tunnel.name}」添加映射 ${endpoint.hostname} → ${endpoint.service}');
    if (routeDns && loggedIn) {
      await routeEndpointDns(tunnelId, endpoint.id, overwrite: overwriteDns);
    } else {
      _toast('映射已保存');
    }
    return true;
  }

  Future<void> updateEndpoint(String tunnelId, TunnelEndpoint updated) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return;
    final index = tunnel.endpoints.indexWhere((e) => e.id == updated.id);
    if (index < 0) return;
    final previous = tunnel.endpoints[index];
    if (previous.hostname.toLowerCase() != updated.hostname.toLowerCase()) {
      updated.dnsRouted = false;
    }
    tunnel.endpoints[index] = updated;
    if (runtimes[tunnelId]?.phase.isLive ?? false) {
      pendingRestart.add(tunnelId);
    }
    await _persist();
    notifyListeners();
    _toast('映射已更新');
  }

  Future<void> removeEndpoint(String tunnelId, String endpointId) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return;
    tunnel.endpoints.removeWhere((e) => e.id == endpointId);
    if (runtimes[tunnelId]?.phase.isLive ?? false) {
      pendingRestart.add(tunnelId);
    }
    await _persist();
    notifyListeners();
    _toast('映射已删除');
  }

  Future<bool> routeEndpointDns(
    String tunnelId,
    String endpointId, {
    bool overwrite = false,
  }) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return false;
    final endpoint = tunnel.endpoints.firstWhere(
      (e) => e.id == endpointId,
      orElse: () => TunnelEndpoint(id: '', hostname: '', port: 0),
    );
    if (endpoint.id.isEmpty) return false;
    if (binaryPath == null || !loggedIn) {
      _toast('请先登录 Cloudflare 账户', error: true);
      return false;
    }
    if (routingEndpoints.contains(endpointId)) return false;
    routingEndpoints.add(endpointId);
    notifyListeners();
    try {
      final result = await cf.routeDns(
        binaryPath!,
        store.certFile.path,
        tunnelId,
        endpoint.hostname,
        overwrite: overwrite,
      );
      if (!result.ok) {
        throw Exception(
          CloudflaredService.friendlyError(
            result.combined,
            fallback: 'DNS 配置失败',
          ),
        );
      }
      endpoint.dnsRouted = true;
      await _persist();
      _sys('DNS 已指向隧道：${endpoint.hostname}');
      _toast('DNS 已配置：${endpoint.hostname}');
      return true;
    } catch (error) {
      final message = '$error'.replaceFirst('Exception: ', '');
      _toast('DNS 配置失败：$message', error: true);
      _sys('DNS 配置失败：$message', level: LogLevel.error);
      return false;
    } finally {
      routingEndpoints.remove(endpointId);
      notifyListeners();
    }
  }

  Future<void> routeAllDns(String tunnelId) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return;
    for (final endpoint in List.of(tunnel.endpoints)) {
      if (!endpoint.dnsRouted) {
        await routeEndpointDns(tunnelId, endpoint.id);
      }
    }
  }

  // ---------------------------------------------------------------- 进程

  Future<void> startTunnel(String tunnelId) async {
    final tunnel = _tunnelById(tunnelId);
    if (tunnel == null) return;
    final runtime = runtimes[tunnelId];
    if (runtime == null || runtime.phase.isLive) return;
    if (binaryPath == null) {
      _toast('cloudflared 运行时未就绪', error: true);
      return;
    }
    if (!await File(tunnel.credentialsPath).exists()) {
      // 换机器或清理过数据：先尝试从云端取回同一隧道的凭证。
      final restored = await _fetchCredentials(tunnel);
      if (!restored || !await File(tunnel.credentialsPath).exists()) {
        missingCredentials.add(tunnelId);
        _toast('隧道凭证缺失且无法从云端取回，请确认隧道仍然存在', error: true);
        notifyListeners();
        return;
      }
      missingCredentials.remove(tunnelId);
    }
    if (tunnel.endpoints.isEmpty) {
      _toast('请先添加至少一个端口映射', error: true);
      return;
    }
    runtime.phase = TunnelPhase.starting;
    runtime.error = null;
    runtime.connections.clear();
    runtime.pid = null;
    runtime.startedAt = DateTime.now();
    runtime.logs.clear();
    pendingRestart.remove(tunnelId);
    notifyListeners();
    _sys('正在启动隧道「${tunnel.name}」…');
    try {
      final configPath = await cf.writeConfig(tunnel);
      final command = await launcher.wrap(binaryPath!, [
        'tunnel',
        '--config',
        configPath,
        '--origincert',
        store.certFile.path,
        '--no-autoupdate',
        'run',
        tunnelId,
      ]);
      final process = await Process.start(
        command.executable,
        command.args,
        environment: command.environment,
      );
      _processes[tunnelId] = process;
      runtime.pid = process.pid;
      _devLog('tunnel "${tunnel.name}" started pid=${process.pid}');
      _sys('隧道「${tunnel.name}」进程已启动 (PID ${process.pid})');
      _wire(process.stdout, (line) => _handleTunnelLine(tunnel, runtime, line));
      _wire(process.stderr, (line) => _handleTunnelLine(tunnel, runtime, line));
      unawaited(
        process.exitCode.then((code) {
          if (_processes[tunnelId] != process) return;
          _processes.remove(tunnelId);
          runtime.pid = null;
          runtime.connections.clear();
          if (runtime.phase != TunnelPhase.stopped) {
            runtime.phase = code == 0 ? TunnelPhase.stopped : TunnelPhase.error;
            if (code != 0) {
              runtime.error = '进程已退出（代码 $code）';
              _sys('隧道「${tunnel.name}」异常退出，代码 $code', level: LogLevel.error);
            } else {
              _sys('隧道「${tunnel.name}」已停止');
            }
          }
          notifyListeners();
        }),
      );
      notifyListeners();
    } catch (error) {
      runtime.phase = TunnelPhase.error;
      runtime.error = '$error';
      _processes.remove(tunnelId);
      notifyListeners();
      _sys('启动隧道失败：$error', level: LogLevel.error);
      _toast('启动失败：$error', error: true);
    }
  }

  Future<void> stopTunnel(String tunnelId) async {
    final runtime = runtimes[tunnelId];
    final tunnel = _tunnelById(tunnelId);
    final process = _processes.remove(tunnelId);
    if (runtime != null) {
      runtime.phase = TunnelPhase.stopped;
      runtime.pid = null;
      runtime.connections.clear();
      runtime.error = null;
      pendingRestart.remove(tunnelId);
    }
    if (process != null) {
      process.kill();
    }
    notifyListeners();
    if (tunnel != null && process != null) {
      _sys('已停止隧道「${tunnel.name}」');
    }
  }

  Future<void> toggleTunnel(String tunnelId) async {
    final runtime = runtimes[tunnelId];
    if (runtime == null) return;
    if (runtime.phase.isLive) {
      await stopTunnel(tunnelId);
    } else {
      await startTunnel(tunnelId);
    }
  }

  Future<void> startAllTunnels() async {
    for (final tunnel in tunnels) {
      if (!(runtimes[tunnel.id]?.phase.isLive ?? false) &&
          tunnel.endpoints.isNotEmpty) {
        await startTunnel(tunnel.id);
      }
    }
  }

  Future<void> stopAllTunnels() async {
    await stopQuickTunnel();
    for (final tunnelId in _processes.keys.toList()) {
      await stopTunnel(tunnelId);
    }
    for (final runtime in runtimes.values) {
      if (runtime.phase.isLive) {
        runtime.phase = TunnelPhase.stopped;
        runtime.connections.clear();
        runtime.pid = null;
      }
    }
    notifyListeners();
  }

  Future<void> startQuickTunnel(int port) async {
    if (quick.phase.isLive) return;
    if (binaryPath == null) {
      _toast('运行时尚未就绪', error: true);
      return;
    }
    if (!isValidPort(port)) {
      _toast('端口号无效', error: true);
      return;
    }
    settings.quickPort = port;
    await store.saveSettings(settings);
    quick.phase = TunnelPhase.starting;
    quick.url = null;
    quick.error = null;
    quick.pid = null;
    quick.logs.clear();
    notifyListeners();
    _sys('正在创建临时隧道 → localhost:$port');
    try {
      final command = await launcher.wrap(binaryPath!, [
        'tunnel',
        '--no-autoupdate',
        '--url',
        'http://localhost:$port',
      ]);
      final process = await Process.start(
        command.executable,
        command.args,
        environment: command.environment,
      );
      _quickProcess = process;
      quick.pid = process.pid;
      _wire(process.stdout, _handleQuickLine);
      _wire(process.stderr, _handleQuickLine);
      unawaited(
        process.exitCode.then((code) {
          if (_quickProcess != process) return;
          _quickProcess = null;
          quick.pid = null;
          if (quick.phase != TunnelPhase.stopped) {
            quick.phase = code == 0 ? TunnelPhase.stopped : TunnelPhase.error;
            if (code != 0) {
              quick.error = '进程已退出（代码 $code）';
              _sys('临时隧道异常退出，代码 $code', level: LogLevel.error);
            }
          }
          notifyListeners();
        }),
      );
      notifyListeners();
    } catch (error) {
      quick.phase = TunnelPhase.error;
      quick.error = '$error';
      notifyListeners();
      _toast('临时隧道启动失败：$error', error: true);
    }
  }

  Future<void> stopQuickTunnel() async {
    final process = _quickProcess;
    _quickProcess = null;
    quick.phase = TunnelPhase.stopped;
    quick.url = null;
    quick.pid = null;
    quick.error = null;
    process?.kill();
    notifyListeners();
    if (process != null) {
      _sys('已停止临时隧道');
    }
  }

  void _handleTunnelLine(Tunnel tunnel, TunnelRuntime runtime, String line) {
    if (line.trim().isEmpty) return;
    _appendLog(runtime.logs, tunnel.name, line);
    final conn = RegExp(r'connIndex=(\d+)').firstMatch(line);
    final index = conn != null ? int.tryParse(conn.group(1)!) : null;
    if (line.contains('Registered tunnel connection') && index != null) {
      runtime.connections.add(index);
      runtime.phase = TunnelPhase.connected;
      notifyListeners();
    } else if (line.contains('Unregistered tunnel connection') &&
        index != null) {
      runtime.connections.remove(index);
      if (runtime.connections.isEmpty && runtime.phase.isConnected) {
        runtime.phase = TunnelPhase.reconnecting;
      }
      notifyListeners();
    } else if (line.contains('Retrying connection') ||
        line.contains('Registering tunnel connection')) {
      if (runtime.phase.isConnected) {
        runtime.phase = TunnelPhase.reconnecting;
        notifyListeners();
      }
    } else if (line.contains('ERR')) {
      runtime.error = CloudflaredService.friendlyError(line);
      notifyListeners();
    }
    _notifySoon();
  }

  void _handleQuickLine(String line) {
    if (line.trim().isEmpty) return;
    _appendLog(quick.logs, '临时隧道', line);
    final match = RegExp(r'https://([a-z0-9-]+)\.trycloudflare\.com')
        .firstMatch(line);
    if (match != null && match.group(1) != 'api') {
      final url = match.group(0);
      if (quick.url != url) {
        quick.url = url;
        quick.phase = TunnelPhase.connected;
        _devLog('quick tunnel ready: $url -> localhost:${settings.quickPort}');
        notifyListeners();
        _toast('临时公网地址已就绪');
      }
      return;
    }
    if (line.contains('ERR') && quick.phase == TunnelPhase.starting) {
      quick.error = CloudflaredService.friendlyError(line);
      notifyListeners();
    }
    _notifySoon();
  }

  void _appendLog(List<LogEntry> target, String source, String line) {
    final level = detectLogLevel(line);
    final message = _stripLogPrefix(line.trimRight());
    target.add(
      LogEntry(
        time: DateTime.now(),
        source: source,
        message: message,
        level: level,
      ),
    );
    if (target.length > 600) {
      target.removeRange(0, target.length - 600);
    }
  }

  static final RegExp _logPrefix = RegExp(
    r'^(?:\d{4}-\d{2}-\d{2}T\S+\s+)?(?:INF|ERR|WRN|DBG|FTL)\s+',
  );

  String _stripLogPrefix(String line) {
    final stripped = line.replaceFirst(_logPrefix, '');
    return stripped.isEmpty ? line : stripped;
  }

  void _wire(Stream<List<int>> stream, void Function(String line) handler) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          handler,
          onError: (Object error) {
            _sys('读取 cloudflared 输出失败：$error', level: LogLevel.debug);
          },
        );
  }

  void _sys(String message, {LogLevel level = LogLevel.info}) {
    systemLogs.add(
      LogEntry(
        time: DateTime.now(),
        source: '系统',
        message: message,
        level: level,
      ),
    );
    if (systemLogs.length > 400) {
      systemLogs.removeRange(0, systemLogs.length - 400);
    }
    _notifySoon();
  }

  void _notifySoon() {
    _logNotifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _logNotifyTimer = null;
      logRevision.value++;
    });
  }

  void _trimIdleLogs() {
    if (systemLogs.length > 400) {
      systemLogs.removeRange(0, systemLogs.length - 400);
    }
  }

  Tunnel? _tunnelById(String id) {
    for (final tunnel in tunnels) {
      if (tunnel.id == id) return tunnel;
    }
    return null;
  }

  Future<void> _persist() async {
    try {
      await store.saveTunnels(tunnels);
    } catch (error) {
      _sys('保存配置失败：$error', level: LogLevel.error);
    }
  }

  void clearLogs() {
    systemLogs.clear();
    quick.logs.clear();
    for (final runtime in runtimes.values) {
      runtime.logs.clear();
    }
    notifyListeners();
  }

  bool get canOpenDataFolder =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> openDataFolder() async {
    if (!canOpenDataFolder) {
      _toast('当前平台不支持打开数据目录', error: true);
      return;
    }
    final command = Platform.isWindows
        ? 'explorer.exe'
        : (Platform.isMacOS ? 'open' : 'xdg-open');
    try {
      await Process.start(command, [store.root.path]);
    } catch (error) {
      _toast('无法打开目录：$error', error: true);
    }
  }

  Future<void> openUrl(String url) => _open(url);

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      _toast('无法打开链接：$url', error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!_messages.isClosed) {
      _messages.add(UiMessage(text, error: error));
    }
  }

  /// 平台控制台输出（Android logcat tag: flutter，前缀 [cf-tunnel]），便于移动端排查。
  void _devLog(String message) {
    developer.log(message, name: 'cf-tunnel');
    debugPrint('[cf-tunnel] $message');
  }

  /// Android 上只要有隧道在跑就挂住前台服务，避免后台被系统回收。
  @override
  void notifyListeners() {
    if (Platform.isAndroid) {
      unawaited(PlatformBridge.setKeepAlive(anyTunnelRunning));
    }
    _refreshTrayTooltip();
    super.notifyListeners();
  }

  Future<void> shutdown() async {
    await stopAllTunnels();
    _loginWatch?.cancel();
    _loginProcess?.kill();
    _loginWatch = null;
    _loginProcess = null;
    _logNotifyTimer?.cancel();
    _logNotifyTimer = null;
  }

  @override
  void dispose() {
    WindowChrome.clearQuitRequest();
    _loginWatch?.cancel();
    _loginProcess?.kill();
    _quickProcess?.kill();
    for (final process in _processes.values) {
      process.kill();
    }
    _logNotifyTimer?.cancel();
    _messages.close();
    logRevision.dispose();
    super.dispose();
  }
}
