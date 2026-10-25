import 'dart:math' as math;

/// 隧道进程所处阶段。
enum TunnelPhase { stopped, starting, connected, reconnecting, error }

extension TunnelPhaseInfo on TunnelPhase {
  bool get isStarting => this == TunnelPhase.starting;
  bool get isConnected => this == TunnelPhase.connected;
  bool get isReconnecting => this == TunnelPhase.reconnecting;
  bool get isError => this == TunnelPhase.error;
  bool get isLive => isStarting || isConnected || isReconnecting;

  String get label => switch (this) {
        TunnelPhase.stopped => '已停止',
        TunnelPhase.starting => '连接中',
        TunnelPhase.connected => '已连接',
        TunnelPhase.reconnecting => '重连中',
        TunnelPhase.error => '异常',
      };
}

enum LogLevel { info, warn, error, debug }

LogLevel detectLogLevel(String line) {
  final upper = line.toUpperCase();
  if (upper.contains(' ERR ') ||
      upper.startsWith('ERR ') ||
      upper.contains(' FTL ') ||
      upper.contains('ERROR')) {
    return LogLevel.error;
  }
  if (upper.contains(' WRN ') || upper.contains('WARN')) return LogLevel.warn;
  if (upper.contains(' DBG ') || upper.contains('DEBUG')) return LogLevel.debug;
  return LogLevel.info;
}

class LogEntry {
  LogEntry({
    required this.time,
    required this.source,
    required this.message,
    this.level = LogLevel.info,
  });

  final DateTime time;
  final String source;
  final String message;
  final LogLevel level;

  String get timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String get plain => '[$timeLabel] [$source] ${level.name.toUpperCase()} $message';
}

class TunnelEndpoint {
  TunnelEndpoint({
    required this.id,
    required this.hostname,
    required this.port,
    this.scheme = 'http',
    this.path,
    this.dnsRouted = false,
  });

  final String id;
  String hostname;
  int port;
  String scheme;
  String? path;
  bool dnsRouted;

  String get service => '$scheme://localhost:$port';
  String get publicUrl => 'https://$hostname${path ?? ''}';
  String get localUrl => '$service${path ?? ''}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostname': hostname,
        'port': port,
        'scheme': scheme,
        'path': path,
        'dnsRouted': dnsRouted,
      };

  factory TunnelEndpoint.fromJson(Map<String, dynamic> json) => TunnelEndpoint(
        id: json['id'] as String? ?? newId(),
        hostname: json['hostname'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 8080,
        scheme: json['scheme'] as String? ?? 'http',
        path: json['path'] as String?,
        dnsRouted: json['dnsRouted'] as bool? ?? false,
      );
}

class Tunnel {
  Tunnel({
    required this.id,
    required this.name,
    required this.credentialsPath,
    List<TunnelEndpoint>? endpoints,
    DateTime? createdAt,
  })  : endpoints = endpoints ?? <TunnelEndpoint>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final String credentialsPath;
  List<TunnelEndpoint> endpoints;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'credentialsPath': credentialsPath,
        'endpoints': endpoints.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Tunnel.fromJson(Map<String, dynamic> json) => Tunnel(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'tunnel',
        credentialsPath: json['credentialsPath'] as String? ?? '',
        endpoints: (json['endpoints'] as List<dynamic>? ?? [])
            .map((e) => TunnelEndpoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class TunnelRuntime {
  TunnelPhase phase = TunnelPhase.stopped;
  int? pid;
  DateTime? startedAt;
  String? error;
  final Set<int> connections = <int>{};
  final List<LogEntry> logs = <LogEntry>[];

  int get connectionCount => connections.length;
}

class QuickTunnelRuntime {
  TunnelPhase phase = TunnelPhase.stopped;
  int? pid;
  String? url;
  String? error;
  final List<LogEntry> logs = <LogEntry>[];

  int get connectionCount => phase == TunnelPhase.connected ? 1 : 0;
}

class AppSettings {
  AppSettings({
    this.themeMode = 'dark',
    this.binaryPath,
    this.quickPort = 8080,
    this.autoStartTunnels = false,
    this.minimizeToTray = true,
    this.autoStartOnBoot = false,
  });

  String themeMode;
  String? binaryPath;
  int quickPort;
  bool autoStartTunnels;

  /// Windows：点关闭只隐藏窗口，隧道继续后台运行。
  bool minimizeToTray;

  /// Windows：登录系统后静默启动应用。
  bool autoStartOnBoot;

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'binaryPath': binaryPath,
        'quickPort': quickPort,
        'autoStartTunnels': autoStartTunnels,
        'minimizeToTray': minimizeToTray,
        'autoStartOnBoot': autoStartOnBoot,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: json['themeMode'] as String? ?? 'dark',
        binaryPath: json['binaryPath'] as String?,
        quickPort: (json['quickPort'] as num?)?.toInt() ?? 8080,
        autoStartTunnels: json['autoStartTunnels'] as bool? ?? false,
        minimizeToTray: json['minimizeToTray'] as bool? ?? true,
        autoStartOnBoot: json['autoStartOnBoot'] as bool? ?? false,
      );
}

final math.Random _rng = math.Random.secure();

String newId() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(10, (_) => alphabet[_rng.nextInt(alphabet.length)]).join();
}

String shortId(String id) => id.length <= 10 ? id : '${id.substring(0, 8)}…';

bool isValidHostname(String value) {
  final v = value.trim();
  if (v.isEmpty || v.contains('://') || v.contains('/') || v.contains(' ')) {
    return false;
  }
  final re = RegExp(r'^(?=.{4,253}$)([a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$');
  return re.hasMatch(v);
}

bool isValidPort(int? value) => value != null && value >= 1 && value <= 65535;

bool isValidTunnelName(String value) {
  return RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$').hasMatch(value);
}
