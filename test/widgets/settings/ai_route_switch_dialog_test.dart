import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_route_switch_dialog.dart';

import '../../helpers/settings.dart';

void main() {
  testWidgets('values the new route had before come back', (tester) async {
    useTempSupportDir();
    final model =
        AiModelEntry.create(
              upstream: 'gemini-2.5-pro',
              route: AiProviderType.googleGenAi,
            )
            .withCurrentParams(const RouteParams(maxOutputTokens: 4096))
            .switchedTo(AiProviderType.openAi)
            .withCurrentParams(const RouteParams(maxOutputTokens: 1234))
            .switchedTo(AiProviderType.googleGenAi);
    final channel =
        AiChannel.create(
          platform: PlatformProfiles.google,
          name: 'g',
          apiKey: 'k',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.googleGenAi),
            AiRoute(protocol: AiProviderType.openAi),
          ],
          models: [model],
        );

    await pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel: channel,
        model: model,
        to: AiProviderType.openAi,
      ),
      profiles: AiProfilesService(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('4096'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    // The target route was configured, so nothing reads as unset.
    expect(find.text('not set · not sent'), findsNothing);
  });

  testWidgets('a platform switch the model refused is not named', (
    tester,
  ) async {
    useTempSupportDir();
    final model = AiModelEntry.create(
      upstream: 'glm-5.3',
      route: AiProviderType.openAi,
    );
    final channel =
        AiChannel.create(
          platform: PlatformProfiles.zhipu,
          name: 'z',
          apiKey: 'k',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.openAi),
            AiRoute(protocol: AiProviderType.anthropic),
          ],
          models: [model],
        );
    Future<void> pump() => pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel: channel,
        model: model,
        to: AiProviderType.anthropic,
      ),
      profiles: AiProfilesService(),
    );

    await pump();
    expect(find.text('off · thinking'), findsOneWidget);

    // glm-5.3 always reasons: off sends nothing, so no field is named.
    final provider = AiService.providerFor(channel.configFor(model));
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.openAi.id,
        base: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-5.3',
        apiKey: 'k',
      ),
      (b) => b.copyWith(thinkingOffTried: {LearnedBehaviour.dialectOff}),
    );
    const written = {LearnedBehaviour.dialectOff};
    expect(
      provider.learned.thinkingOffTried,
      written,
      reason: 'the test wrote the route the dialog reads',
    );
    await pump();
    expect(find.text('off · thinking'), findsNothing);
  });

  testWidgets('a switch route that refused on still names the field for off', (
    tester,
  ) async {
    useTempSupportDir();
    AiModelEntry model({required bool thinking}) =>
        AiModelEntry.create(
          upstream: 'MiniMax-M3',
          route: AiProviderType.anthropic,
        ).copyWith(
          params: {
            AiProviderType.anthropic: RouteParams(thinkingEnabled: thinking),
          },
        );
    AiChannel channel(AiModelEntry m) =>
        AiChannel.create(
          platform: PlatformProfiles.miniMax,
          name: 'mm',
          apiKey: 'k-dialog',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.anthropic),
            AiRoute(protocol: AiProviderType.openAi),
          ],
          models: [m],
        );
    final off = model(thinking: false);
    final config = channel(off).configFor(off);
    final provider = AiService.providerFor(config);
    addTearDown(provider.forgetLearned);
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: '${config.endpoint}/v1',
        model: 'MiniMax-M3',
        apiKey: 'k-dialog',
      ),
      (b) => b.copyWith(rejectedFields: {'thinking:adaptive'}),
    );
    const written = {'thinking:adaptive'};
    expect(
      provider.learned.rejectedFields,
      written,
      reason: 'the test wrote the route the dialog reads',
    );

    Future<void> pump(AiModelEntry m) => pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel: channel(m),
        model: m,
        to: AiProviderType.openAi,
      ),
      profiles: AiProfilesService(),
    );

    // Off still goes out as `thinking: {type: "disabled"}`.
    await pump(off);
    expect(find.text('off · thinking'), findsOneWidget);
    // On is no longer sent: nothing to name.
    await pump(model(thinking: true));
    expect(find.text('on · thinking'), findsNothing);
    expect(find.text('on'), findsOneWidget);
  });
}
