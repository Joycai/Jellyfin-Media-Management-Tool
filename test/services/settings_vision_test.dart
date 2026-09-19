import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';

AiConfig _model(String name) => AiConfig(
  provider: AiProviderType.openAi,
  endpoint: 'http://localhost:1234/v1',
  apiKey: '',
  model: name,
);

/// Frames leave the computer, so sending them needs the user's say-so for
/// the very model they go to.
void main() {
  test('is off for a config written before the setting existed', () {
    final settings = SettingsService()..applyConfig({'glass_intensity': 70});
    expect(settings.visionFramesAllowedFor(_model('qwen-vl')), isFalse);
  });

  test('consent names one model and does not carry to another', () {
    final settings = SettingsService()
      ..applyConfig({'vision_frames_for': _model('qwen-vl').toolFingerprint});
    expect(settings.visionFramesAllowedFor(_model('qwen-vl')), isTrue);
    expect(settings.visionFramesAllowedFor(_model('cloud-vl')), isFalse);
  });
}
