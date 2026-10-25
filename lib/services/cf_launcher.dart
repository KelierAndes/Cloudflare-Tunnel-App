import 'dart:io';

import 'local_store.dart';
import 'platform_bridge.dart';

/// 一条待执行的 cloudflared 命令。
class CfCommand {
  const CfCommand(this.executable, this.args, {this.environment});

  final String executable;
  final List<String> args;
  final Map<String, String>? environment;
}

/// 统一构造 cloudflared 命令。
///
/// Android 上的 cloudflared 是随 APK 打包的 Linux 二进制：
/// - 没有 `/etc/resolv.conf`，Go 的解析器会把查询发到 `[::1]:53` 而失败；
///   这里把系统 DNS 通过 `CF_DNS_SERVER` 传给它（随包的 Android 构建会读取，
///   见 `cmd/cloudflared/main.go` 里的 useEnvDNSServer）。
/// - `login` 会把证书写到 `$HOME/.cloudflared`，所以 HOME 指向数据目录。
///
/// 其他平台原样执行。
class CfLauncher {
  CfLauncher(this.store);

  final LocalStore store;

  bool get isAndroid => Platform.isAndroid;

  Future<CfCommand> wrap(String binary, List<String> args) async {
    if (!isAndroid) return CfCommand(binary, args);
    final env = <String, String>{'HOME': store.homeDir.path};
    final server = await _dnsServer();
    if (server != null) env['CF_DNS_SERVER'] = server;
    return CfCommand(binary, args, environment: env);
  }

  /// 取一个可用的系统 DNS（优先 IPv4），拼成 host:port。
  Future<String?> _dnsServer() async {
    final servers = await PlatformBridge.dnsServers();
    if (servers.isEmpty) return null;
    final ipv4 = servers.where((s) => !s.contains(':')).toList();
    final chosen = ipv4.isNotEmpty ? ipv4.first : servers.first;
    return chosen.contains(':') ? '[$chosen]:53' : '$chosen:53';
  }
}
