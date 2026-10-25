import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'cf_launcher.dart';
import 'local_store.dart';

class CfResult {
  CfResult(this.exitCode, this.out, this.err);

  final int exitCode;
  final String out;
  final String err;

  bool get ok => exitCode == 0;

  String get combined {
    final parts = <String>[];
    if (out.trim().isNotEmpty) parts.add(out.trim());
    if (err.trim().isNotEmpty) parts.add(err.trim());
    return parts.join('\n');
  }
}

class RemoteTunnel {
  const RemoteTunnel({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;
}

/// 解析 `cloudflared tunnel list --output json` 的结果，字段命名做兼容处理。
List<RemoteTunnel> parseRemoteTunnels(String raw) {
  final start = raw.indexOf('[');
  if (start < 0) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start));
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final tunnels = <RemoteTunnel>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = (item['id'] ?? item['UUID'] ?? item['uuid'])?.toString();
    if (id == null || id.isEmpty) continue;
    final name = (item['name'] ?? item['Name'] ?? '').toString();
    final created = (item['created_at'] ?? item['createdAt'])?.toString();
    tunnels.add(
      RemoteTunnel(
        id: id,
        name: name.isEmpty ? id.substring(0, 8) : name,
        createdAt: created == null
            ? null
            : DateTime.tryParse(created)?.toLocal(),
      ),
    );
  }
  return tunnels;
}

/// 对 cloudflared 命令行的一层薄封装。
class CloudflaredService {
  CloudflaredService(this.store, this.launcher);

  final LocalStore store;
  final CfLauncher launcher;

  static final RegExp _logPrefix = RegExp(
    r'^(?:\d{4}-\d\d-\d\dT\S+\s+)?(?:INF|ERR|WRN|DBG|FTL)\s+',
    caseSensitive: false,
  );

  static String friendlyError(String raw, {String fallback = '操作失败'}) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return fallback;
    String line = lines.last;
    for (final candidate in lines.reversed) {
      if (candidate.contains('ERR') || candidate.contains('failed')) {
        line = candidate;
        break;
      }
    }
    line = line.replaceFirst(_logPrefix, '');
    if (line.length > 260) line = '${line.substring(0, 257)}...';
    return line.isEmpty ? fallback : line;
  }

  Future<String?> version(String binary) async {
    try {
      final command = await launcher.wrap(binary, ['--version']);
      final result = await Process.run(
        command.executable,
        command.args,
        environment: command.environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        debugPrint(
          'cloudflared --version 退出码 ${result.exitCode}：${result.stderr}',
        );
        return null;
      }
      final text = '${result.stdout}'.trim();
      final match = RegExp(r'version\s+(\S+)').firstMatch(text);
      return match?.group(1) ?? (text.isEmpty ? null : text.split('\n').first);
    } catch (_) {
      return null;
    }
  }

  Future<CfResult> listTunnels(String binary, String certPath) async {
    return _run(binary, [
      'tunnel',
      '--origincert',
      certPath,
      'list',
      '--output',
      'json',
    ]);
  }

  Future<CfResult> createTunnel(
    String binary,
    String certPath,
    String name,
    String credentialsPath,
  ) async {
    return _run(binary, [
      'tunnel',
      '--origincert',
      certPath,
      'create',
      '--output',
      'json',
      '--credentials-file',
      credentialsPath,
      name,
    ]);
  }

  Future<CfResult> routeDns(
    String binary,
    String certPath,
    String tunnelId,
    String hostname, {
    bool overwrite = false,
  }) async {
    return _run(binary, [
      'tunnel',
      '--origincert',
      certPath,
      'route',
      'dns',
      if (overwrite) '--overwrite-dns',
      tunnelId,
      hostname,
    ]);
  }

  /// 从云端取回已有隧道的凭证文件，用于导入隧道或修复丢失的凭证。
  Future<CfResult> fetchCredentials(
    String binary,
    String certPath,
    String tunnelId,
    String credentialsPath,
  ) async {
    return _run(binary, [
      'tunnel',
      '--origincert',
      certPath,
      'token',
      '--credentials-file',
      credentialsPath,
      tunnelId,
    ]);
  }

  Future<CfResult> cleanupTunnel(
    String binary,
    String certPath,
    String tunnelId,
  ) async {
    return _run(binary, [
      'tunnel',
      '--origincert',
      certPath,
      'cleanup',
      tunnelId,
    ]);
  }

  Future<CfResult> deleteTunnel(
    String binary,
    String certPath,
    String tunnelId,
  ) async {
    return _run(binary, [
      'tunnel',
      '--origincert',
      certPath,
      'delete',
      '-f',
      tunnelId,
    ]);
  }

  Future<CfResult> _run(String binary, List<String> args) async {
    try {
      final command = await launcher.wrap(binary, args);
      final result = await Process.run(
        command.executable,
        command.args,
        environment: command.environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return CfResult(result.exitCode, '${result.stdout}', '${result.stderr}');
    } on ProcessException catch (error) {
      return CfResult(-1, '', error.message);
    }
  }

  /// 为命名隧道生成 ingress 配置。Windows 路径统一为 / 避免 YAML 转义问题。
  Future<String> writeConfig(Tunnel tunnel) async {
    final buffer = StringBuffer();
    buffer.writeln('# generated by Cloudflare Tunnel Manager');
    buffer.writeln('tunnel: ${tunnel.id}');
    final cred = tunnel.credentialsPath
        .replaceAll('\\', '/')
        .replaceAll("'", "''");
    buffer.writeln("credentials-file: '$cred'");
    buffer.writeln('ingress:');
    for (final endpoint in tunnel.endpoints) {
      buffer.writeln('  - hostname: ${endpoint.hostname}');
      if ((endpoint.path ?? '').trim().isNotEmpty) {
        buffer.writeln('    path: ${endpoint.path!.trim()}');
      }
      buffer.writeln('    service: ${endpoint.service}');
    }
    buffer.writeln('  - service: http_status:404');
    final path = store.configPathFor(tunnel.id);
    final file = File(path);
    await file.writeAsString(buffer.toString(), flush: true);
    return path;
  }

  static String defaultCertPath() {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return home.isEmpty
        ? ''
        : '$home${Platform.pathSeparator}.cloudflared${Platform.pathSeparator}cert.pem';
  }

  /// 从 GitHub 下载官方 cloudflared，回调为 0..1 的进度。
  Future<void> downloadRuntime(
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    final url = downloadUrl();
    final tmp = File('${target.path}.download');
    if (await tmp.exists()) await tmp.delete();
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('下载失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      var lastBucket = -1;
      sink = tmp.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final denominator = total > 0 ? total : 1;
        final progress = (received / denominator).clamp(0.0, 1.0);
        final bucket = (progress * 100).floor();
        if (bucket != lastBucket) {
          lastBucket = bucket;
          onProgress?.call(progress);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received < 1024 * 1024) {
        throw Exception('下载内容异常，请稍后重试');
      }
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['755', target.path]);
        } catch (_) {}
      }
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    } finally {
      if (sink != null) {
        await sink.close();
      }
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      client.close();
    }
  }

  static String downloadUrl() {
    final target = platformTarget();
    final ext = target.os == 'windows' ? '.exe' : '';
    return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${target.os}-${target.arch}$ext';
  }

  /// 当前平台对应的 cloudflared 发布产物标识（Android 复用 linux 静态构建）。
  static ({String os, String arch}) platformTarget() {
    var abi = Abi.current();
    if (Platform.isWindows) {
      return (os: 'windows', arch: abi == Abi.windowsArm64 ? 'arm64' : 'amd64');
    }
    if (Platform.isAndroid) {
      return (os: 'linux', arch: abi == Abi.androidArm64 ? 'arm64' : 'amd64');
    }
    if (Platform.isMacOS) {
      return (os: 'darwin', arch: abi == Abi.macosArm64 ? 'arm64' : 'amd64');
    }
    return (os: 'linux', arch: abi == Abi.linuxArm64 ? 'arm64' : 'amd64');
  }

  /// 应用内打包的运行时资源名；非 Windows 平台默认不打包，改为下载。
  static String get bundledAssetName => Platform.isWindows
      ? 'assets/bin/cloudflared.exe'
      : 'assets/bin/cloudflared';

  static bool get supportsBundledRuntime => Platform.isWindows;
}
