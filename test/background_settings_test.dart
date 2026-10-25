import 'package:cf_tunnel_manager/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('后台运行设置：默认最小化到托盘、不开机自启', () {
    final settings = AppSettings();
    expect(settings.minimizeToTray, isTrue);
    expect(settings.autoStartOnBoot, isFalse);
  });

  test('旧版本 settings.json 缺少新字段时按默认值补齐', () {
    final legacy = AppSettings.fromJson({'themeMode': 'light', 'quickPort': 9000});
    expect(legacy.themeMode, 'light');
    expect(legacy.quickPort, 9000);
    expect(legacy.minimizeToTray, isTrue);
    expect(legacy.autoStartOnBoot, isFalse);
  });

  test('后台运行设置可往返序列化', () {
    final restored = AppSettings.fromJson(
      AppSettings(minimizeToTray: false, autoStartOnBoot: true).toJson(),
    );
    expect(restored.minimizeToTray, isFalse);
    expect(restored.autoStartOnBoot, isTrue);
  });
}
