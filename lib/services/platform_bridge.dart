import 'dart:io';

import 'package:flutter/services.dart';

/// 与 Android 宿主交互：可执行文件目录与前台保活服务。
class PlatformBridge {
  static const MethodChannel _channel = MethodChannel('cf_tunnel/device');
  static bool? _keepAliveOn;

  /// Android 上随 APK 解压出的 nativeLibraryDir（cloudflared 以 libcloudflared.so 发布）。
  static Future<String?> nativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('nativeLibraryDir');
    } catch (error) {
      return null;
    }
  }

  static Future<void> setKeepAlive(bool on) async {
    if (!Platform.isAndroid || _keepAliveOn == on) return;
    _keepAliveOn = on;
    try {
      await _channel.invokeMethod<bool>(
        on ? 'startKeepAlive' : 'stopKeepAlive',
      );
    } catch (_) {
      _keepAliveOn = null;
    }
  }

  /// 当前网络的 DNS 服务器。Android 不提供 /etc/resolv.conf，只能从系统 API 取。
  static Future<List<String>> dnsServers() async {
    if (!Platform.isAndroid) return const [];
    try {
      final servers = await _channel.invokeListMethod<String>('dnsServers');
      return servers ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
