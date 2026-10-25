import 'package:flutter_test/flutter_test.dart';
import 'package:cf_tunnel_manager/models/models.dart';

void main() {
  group('域名与端口校验', () {
    test('接受合法的公网域名', () {
      expect(isValidHostname('app.example.com'), isTrue);
      expect(isValidHostname('nas.home.example.co.uk'), isTrue);
    });

    test('拒绝包含协议、路径或空格的域名', () {
      expect(isValidHostname('https://app.example.com'), isFalse);
      expect(isValidHostname('app.example.com/api'), isFalse);
      expect(isValidHostname('app example.com'), isFalse);
      expect(isValidHostname(''), isFalse);
    });

    test('端口范围', () {
      expect(isValidPort(8080), isTrue);
      expect(isValidPort(0), isFalse);
      expect(isValidPort(65536), isFalse);
      expect(isValidPort(null), isFalse);
    });

    test('隧道名称', () {
      expect(isValidTunnelName('home-nas'), isTrue);
      expect(isValidTunnelName('dev1'), isTrue);
      expect(isValidTunnelName('-bad'), isFalse);
      expect(isValidTunnelName('Bad Name'), isFalse);
    });
  });

  test('端口映射生成公开地址与本地服务地址', () {
    final endpoint = TunnelEndpoint(
      id: 'x',
      hostname: 'app.example.com',
      port: 3000,
      path: '/api',
    );
    expect(endpoint.publicUrl, 'https://app.example.com/api');
    expect(endpoint.service, 'http://localhost:3000');
    expect(endpoint.localUrl, 'http://localhost:3000/api');

    final restored = TunnelEndpoint.fromJson(endpoint.toJson());
    expect(restored.hostname, endpoint.hostname);
    expect(restored.port, endpoint.port);
    expect(restored.path, endpoint.path);
  });
}
