import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations_en.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_settings_widgets.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_controls.dart';

import '../../helpers/settings.dart';

void main() {
  test('generic platforms are named in the UI language', () {
    final l10n = AppLocalizationsEn();
    expect(platformName(l10n, PlatformProfiles.relay), l10n.aiPlatformRelay);
    expect(platformName(l10n, PlatformProfiles.openAi), 'OpenAI');
  });

  test('only protocols with an adapter are in this build', () {
    expect(protocolInBuild(AiProviderType.openAi), isTrue);
    expect(protocolInBuild(AiProviderType.googleGenAi), isTrue);
  });

  Future<AppToggle> reasoningSwitch(
    WidgetTester tester, {
    required SamplingPreset? preset,
    required bool platformSwitch,
  }) async {
    final controllers = {
      for (final field in SamplingField.values) field: TextEditingController(),
    };
    addTearDown(() {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
    await pumpAiPage(
      tester,
      SingleChildScrollView(
        child: AiSamplingSection(
          preset: preset,
          controllers: controllers,
          thinking: false,
          platformSwitch: platformSwitch,
          lastReasoned: null,
          serverKind: null,
          refused: const {'top_k'},
          onChanged: () {},
          onThinkingChanged: (_) {},
          onReset: () {},
        ),
      ),
      profiles: AiProfilesService(),
    );
    return tester.widget<AppToggle>(find.byType(AppToggle));
  }

  testWidgets('an unknown model is switchable only on a platform switch', (
    tester,
  ) async {
    expect(
      (await reasoningSwitch(
        tester,
        preset: null,
        platformSwitch: true,
      )).onChanged,
      isNotNull,
    );
    expect(
      (await reasoningSwitch(
        tester,
        preset: null,
        platformSwitch: false,
      )).onChanged,
      isNull,
    );
    // A refused field is named, so the user knows why it is not sent.
    expect(find.textContaining('top_k'), findsOneWidget);
  });
}
