import 'package:flutter_test/flutter_test.dart';
import 'package:cf_tunnel_manager/services/cloudflared_service.dart';
import 'package:cf_tunnel_manager/services/local_store.dart';

void main() {
  test('解析云端隧道列表', () {
    const raw = '''
some log noise
[{"created_at":"2026-01-02T03:04:05Z","id":"7c3f9a52-1a2b-4c5d-8e9f-0a1b2c3d4e5f","name":"home-nas","deleted_at":null},
 {"UUID":"1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d","Name":"dev-api"}]
''';
    final tunnels = parseRemoteTunnels(raw);
    expect(tunnels.length, 2);
    expect(tunnels.first.id, '7c3f9a52-1a2b-4c5d-8e9f-0a1b2c3d4e5f');
    expect(tunnels.first.name, 'home-nas');
    expect(tunnels.first.createdAt, isNotNull);
    // 字段大小写不同的旧版本输出也要能读出来
    expect(tunnels.last.id, '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d');
    expect(tunnels.last.name, 'dev-api');
  });

  test('无法解析时返回空列表而不是抛异常', () {
    expect(parseRemoteTunnels('no json here'), isEmpty);
    expect(parseRemoteTunnels('[not json]'), isEmpty);
    expect(parseRemoteTunnels('[]'), isEmpty);
  });

  test('凭证文件名带 ID 前缀，重名隧道不会互相覆盖', () {
    final a = credentialsFileName('nas', '7c3f9a52-1a2b-4c5d-8e9f-0a1b2c3d4e5f');
    final b = credentialsFileName('nas', '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d');
    expect(a, 'nas-7c3f9a52.json');
    expect(b, 'nas-1a2b3c4d.json');
    expect(credentialsFileName('我的 隧道', 'abcd1234-0000-0000-0000-000000000000'),
        '我的-隧道-abcd1234.json');
  });
}
