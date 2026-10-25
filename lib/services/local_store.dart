import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// 云端隧道允许重名，凭证文件名带上 ID 前缀避免互相覆盖。
String credentialsFileName(String name, String tunnelId) {
  final safe = name
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final digits = tunnelId.replaceAll('-', '');
  final suffix = digits.length >= 8 ? digits.substring(0, 8) : digits;
  return '${safe.isEmpty ? 'tunnel' : safe}-$suffix.json';
}

/// 应用数据目录与本地持久化。
class LocalStore {
  late final Directory root;
  late final Directory binDir;
  late final Directory credentialsDir;
  late final Directory configsDir;

  /// Android 上作为 cloudflared 的 HOME（login 会把证书写到这里）。
  late final Directory homeDir;

  bool _initialized = false;

  bool get initialized => _initialized;

  File get binaryFile => File(
    _join(binDir.path, Platform.isWindows ? 'cloudflared.exe' : 'cloudflared'),
  );
  File get certFile => File(_join(root.path, 'cert.pem'));

  /// `cloudflared tunnel login` 忽略 --origincert，证书固定写到 $HOME/.cloudflared。
  File get defaultCertFile =>
      File(_join(_join(homeDir.path, '.cloudflared'), 'cert.pem'));

  File get _stateFile => File(_join(root.path, 'state.json'));
  File get _settingsFile => File(_join(root.path, 'settings.json'));

  String configPathFor(String tunnelId) =>
      _join(configsDir.path, '$tunnelId.yml');

  /// 云端隧道允许重名，凭证文件名同时带上 ID 前缀避免互相覆盖。
  String credentialsPathFor(String name, String tunnelId) =>
      _join(credentialsDir.path, credentialsFileName(name, tunnelId));

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  Future<void> init() async {
    if (_initialized) return;
    root = await _resolveRoot();
    binDir = Directory(_join(root.path, 'bin'));
    credentialsDir = Directory(_join(root.path, 'credentials'));
    configsDir = Directory(_join(root.path, 'configs'));
    homeDir = Directory(_join(root.path, 'home'));
    await ensureDirs();
    _initialized = true;
  }

  Future<Directory> _resolveRoot() async {
    try {
      final support = await getApplicationSupportDirectory();
      return support;
    } catch (error) {
      debugPrint('无法获取系统应用目录: $error');
    }
    final env = Platform.environment;
    final base = env['APPDATA'] ?? env['LOCALAPPDATA'];
    if (base != null && base.isNotEmpty) {
      return Directory(_join(_join(base, 'CloudflareTunnelManager'), 'data'));
    }
    return Directory(_join(Directory.current.path, 'data'));
  }

  Future<void> ensureDirs() async {
    for (final dir in [
      root,
      binDir,
      credentialsDir,
      configsDir,
      homeDir,
    ]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  List<Tunnel> loadTunnels() {
    try {
      if (!_stateFile.existsSync()) return [];
      final raw = jsonDecode(_stateFile.readAsStringSync());
      if (raw is Map<String, dynamic>) {
        final list = raw['tunnels'];
        if (list is List) {
          return list
              .whereType<Map<String, dynamic>>()
              .map(Tunnel.fromJson)
              .toList();
        }
      }
    } catch (error) {
      debugPrint('读取隧道配置失败: $error');
    }
    return [];
  }

  AppSettings loadSettings() {
    try {
      if (!_settingsFile.existsSync()) return AppSettings();
      final raw = jsonDecode(_settingsFile.readAsStringSync());
      if (raw is Map<String, dynamic>) return AppSettings.fromJson(raw);
    } catch (error) {
      debugPrint('读取设置失败: $error');
    }
    return AppSettings();
  }

  Future<void> saveTunnels(List<Tunnel> tunnels) async {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'tunnels': tunnels.map((t) => t.toJson()).toList(),
    });
    await _writeAtomic(_stateFile, payload);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final payload = const JsonEncoder.withIndent('  ')
        .convert(settings.toJson());
    await _writeAtomic(_settingsFile, payload);
  }

  Future<void> _writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<void> deleteCert() async {
    for (final file in [certFile, defaultCertFile]) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
