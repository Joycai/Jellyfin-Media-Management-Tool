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
    required ReasoningRoute route,
    bool thinking = false,
    bool? lastReasoned,
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
          thinking: thinking,
          route: route,
          lastReasoned: lastReasoned,
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

  testWidgets('an unknown model is switchable only on a working switch', (
    tester,
  ) async {
    for (final route in ReasoningRoute.values) {
      final toggle = await reasoningSwitch(tester, preset: null, route: route);
      expect(
        toggle.onChanged != null,
        route == ReasoningRoute.platformField ||
            route == ReasoningRoute.protocolField ||
            route == ReasoningRoute.onRefused ||
            route == ReasoningRoute.offToDefault,
        reason: '$route',
      );
    }
    // A refused field is named, so the user knows why it is not sent.
    expect(find.textContaining('top_k'), findsOneWidget);
  });

  testWidgets('an unknown model on a refused switch is drawn as it runs', (
    tester,
  ) async {
    Future<bool> drawn(ReasoningRoute route, {required bool saved}) async =>
        (await reasoningSwitch(
          tester,
          preset: null,
          route: route,
          thinking: saved,
        )).value;

    // Off refused: it reasons whatever was saved.
    expect(await drawn(ReasoningRoute.offRefused, saved: false), isTrue);
    // Neither way: nothing asks it to.
    expect(await drawn(ReasoningRoute.refused, saved: true), isFalse);
    // A switch that still works at least one way, and the ladder, show the
    // saved choice.
    for (final route in [
      ReasoningRoute.platformField,
      ReasoningRoute.protocolField,
      ReasoningRoute.onRefused,
      ReasoningRoute.offToDefault,
      ReasoningRoute.ladder,
    ]) {
      for (final saved in [true, false]) {
        expect(await drawn(route, saved: saved), saved, reason: '$route');
      }
    }
  });

  testWidgets('a model that cannot stop reasoning is said to, not told to '
      'turn it off', (tester) async {
    final l10n = AppLocalizationsEn();
    await reasoningSwitch(
      tester,
      preset: null,
      route: ReasoningRoute.offRefused,
      lastReasoned: true,
    );
    expect(find.text(l10n.thinkingAlwaysOn), findsOneWidget);
    expect(find.text(l10n.thinkingStillOn), findsNothing);

    // A working switch that still reasoned is the server's doing.
    await reasoningSwitch(
      tester,
      preset: null,
      route: ReasoningRoute.platformField,
      lastReasoned: true,
    );
    expect(find.text(l10n.thinkingStillOn), findsOneWidget);

    // So is one that was refused by name: the model runs at its default,
    // and the test is how the user finds out that it reasons.
    await reasoningSwitch(
      tester,
      preset: null,
      route: ReasoningRoute.refused,
      lastReasoned: true,
    );
    expect(find.text(l10n.thinkingStillOn), findsOneWidget);
  });

  testWidgets('a preset model keeps its saved choice on a refused switch', (
    tester,
  ) async {
    // Its sampling values follow the saved choice; drawing it otherwise
    // would show values the request does not carry.
    final qwen3 = SamplingPresets.forModel('qwen3-32b')!;
    expect(qwen3.thinkingIsOptional, isTrue);
    final toggle = await reasoningSwitch(
      tester,
      preset: qwen3,
      route: ReasoningRoute.offRefused,
    );
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNotNull);
    expect(find.text(AppLocalizationsEn().thinkingAlwaysOn), findsOneWidget);
  });
}
