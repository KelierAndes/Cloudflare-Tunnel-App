import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows 原生窗口能力：标题栏主题、托盘后台运行与开机自启。
class WindowChrome {
  static const MethodChannel _channel = MethodChannel('cf_tunnel/window');
  static bool? _lastDark;

  /// 只有 Windows 版有托盘和注册表启动项。
  static bool get supportsBackground => !kIsWeb && Platform.isWindows;

  static Future<void> setTitleBarDark(bool dark) async {
    if (_lastDark == dark) return;
    _lastDark = dark;
    try {
      await _channel.invokeMethod<void>('setTitleBarDark', dark);
    } catch (_) {
      _lastDark = null;
    }
  }

  static Future<void> _send(String method, [Object? args]) async {
    if (!supportsBackground) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // 运行器不支持该能力时静默忽略，界面状态以本地设置为准。
    }
  }

  static Future<void> hideToTray() => _send('hideToTray');

  static Future<void> setCloseToTray(bool enabled) =>
      _send('setCloseToTray', enabled);

  static Future<void> setTooltip(String text) => _send('setTooltip', text);

  static Future<void> quit() => _send('quit');

  /// 写入/移除 HKCU 启动项，失败时返回中文提示，成功返回 null。
  static Future<String?> setAutoStart(bool enabled) async {
    if (!supportsBackground) return '当前平台不支持开机自启';
    try {
      final ok =
          await _channel.invokeMethod<bool>('setAutoStart', enabled) ?? false;
      if (ok) return null;
      return '无法写入系统启动项，请检查注册表权限';
    } on PlatformException catch (error) {
      return error.message ?? '设置开机自启失败';
    } catch (_) {
      return '当前构建不支持开机自启';
    }
  }

  static Future<bool> autoStartEnabled() async {
    if (!supportsBackground) return false;
    try {
      return await _channel.invokeMethod<bool>('isAutoStartEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 托盘菜单「退出」先回到 Dart 停掉隧道，再由 [WindowChrome.quit] 关闭进程。
  static void onQuitRequest(Future<void> Function() callback) {
    if (!supportsBackground) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'requestQuit') {
        await callback();
      }
    });
  }

  static void clearQuitRequest() {
    if (!supportsBackground) return;
    _channel.setMethodCallHandler(null);
  }
}
