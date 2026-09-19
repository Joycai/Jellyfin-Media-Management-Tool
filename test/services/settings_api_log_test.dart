import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';

/// The API log records request bodies to disk, so it must stay off unless the
/// user turned it on, and the switch must reach the log itself, not only the
/// settings page.
void main() {
  tearDown(() => ApiLog.instance.enabled = false);

  test('is off for a config written before the setting existed', () {
    final settings = SettingsService()..applyConfig({'glass_intensity': 70});
    expect(settings.apiLogEnabled, isFalse);
    expect(ApiLog.instance.enabled, isFalse);
  });

  test('a stored choice switches the log itself', () {
    final settings = SettingsService()..applyConfig({'api_log_enabled': true});
    expect(settings.apiLogEnabled, isTrue);
    expect(ApiLog.instance.enabled, isTrue);
  });
}
