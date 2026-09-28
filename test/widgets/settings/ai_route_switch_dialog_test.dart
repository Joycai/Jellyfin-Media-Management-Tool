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
    Future<void> pump([AiModelEntry? m]) => pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel: channel.copyWith(models: [m ?? model]),
        model: m ?? model,
        to: AiProviderType.anthropic,
      ),
      profiles: AiProfilesService(),
    );

    // Both of Zhipu's routes switch thinking with a field of that name.
    await pump();
    expect(find.text('off · thinking'), findsNWidgets(2));

    // A model that refused off and the least: off sends nothing on the
    // route that learned it, so no field is named there; the Messages route
    // has not learned it yet.
    final provider = AiService.providerFor(channel.configFor(model));
    addTearDown(provider.forgetLearned);
    const written = {
      LearnedBehaviour.dialectOff,
      LearnedBehaviour.leastEffortOff,
    };
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.openAi.id,
        base: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-5.3',
        apiKey: 'k',
      ),
      (b) => b.copyWith(thinkingOffTried: written),
    );
    expect(
      provider.learned.thinkingOffTried,
      written,
      reason: 'the test wrote the route the dialog reads',
    );
    await pump();
    expect(find.text('off · thinking'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);
    // On is still sent there, so it is still named; the Messages route,
    // with nothing saved on it, starts off and names its field for that.
    await pump(
      model.copyWith(
        params: {
          AiProviderType.openAi: const RouteParams(thinkingEnabled: true),
        },
      ),
    );
    expect(find.text('on · thinking'), findsOneWidget);
    expect(find.text('off · thinking'), findsOneWidget);
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

  testWidgets('a switch route whose model cannot stop names the least for '
      'off', (tester) async {
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
          apiKey: 'k-dialog-least',
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
    const written = {LearnedBehaviour.dialectOff};
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: '${config.endpoint}/v1',
        model: 'MiniMax-M3',
        apiKey: 'k-dialog-least',
      ),
      (b) => b.copyWith(thinkingOffTried: written),
    );
    expect(
      provider.learned.thinkingOffTried,
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

    // Off goes out as `output_config: {effort: "low"}`, and says so.
    await pump(off);
    expect(find.text('off · output_config.effort'), findsOneWidget);
    expect(find.text('off · thinking'), findsNothing);
    // On still goes out as `thinking: {type: "adaptive"}`.
    await pump(model(thinking: true));
    expect(find.text('on · thinking'), findsOneWidget);
    expect(find.text('on · output_config.effort'), findsNothing);

    // Adaptive refused too: on sends nothing, so nothing is named for it,
    // and off still asks for the least.
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: '${config.endpoint}/v1',
        model: 'MiniMax-M3',
        apiKey: 'k-dialog-least',
      ),
      (b) => b.copyWith(rejectedFields: {'thinking:adaptive'}),
    );
    expect(provider.learned.rejectedFields, {'thinking:adaptive'});
    await pump(model(thinking: true));
    expect(find.text('on · thinking'), findsNothing);
    expect(find.text('on'), findsOneWidget);
    await pump(off);
    expect(find.text('off · output_config.effort'), findsOneWidget);
  });

  testWidgets('a switch route whose server does not know thinking names it '
      'neither way', (tester) async {
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
          apiKey: 'k-dialog-unknown',
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
    const written = {'thinking', 'thinking:adaptive', 'thinking:enabled'};
    LearnedStore.instance.update(
      LearnedStore.routeKey(
        protocol: AiProviderType.anthropic.id,
        base: '${config.endpoint}/v1',
        model: 'MiniMax-M3',
        apiKey: 'k-dialog-unknown',
      ),
      (b) => b.copyWith(rejectedFields: written),
    );
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

    // Named neither way; the new route's column carries a choice too.
    await pump(off);
    expect(find.text('off · thinking'), findsNothing);
    expect(find.text('off'), findsNWidgets(2));
    await pump(model(thinking: true));
    expect(find.text('on · thinking'), findsNothing);
    expect(find.text('on'), findsOneWidget);
  });

  testWidgets('a preset family shows the choice its request carries', (
    tester,
  ) async {
    // The saved choice resolved through the family's preset, as the model
    // page draws it and every adapter sends it: a family that always
    // reasons is on however it was saved, one that never reasons is off.
    useTempSupportDir();
    AiModelEntry model(String upstream, {required bool thinking}) =>
        AiModelEntry.create(
          upstream: upstream,
          route: AiProviderType.anthropic,
        ).copyWith(
          params: {
            AiProviderType.anthropic: RouteParams(thinkingEnabled: thinking),
          },
        );
    Future<void> pump(AiModelEntry m) => pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel:
            AiChannel.create(
              platform: PlatformProfiles.relay,
              name: 'r',
              baseUrl: 'https://relay.example.com',
              apiKey: 'k-dialog-family',
            ).copyWith(
              routes: const [
                AiRoute(protocol: AiProviderType.anthropic),
                AiRoute(protocol: AiProviderType.openAi),
              ],
              models: [m],
            ),
        model: m,
        to: AiProviderType.openAi,
      ),
      profiles: AiProfilesService(),
    );

    // Both columns: the current route's request and the new route's, which
    // carries a choice before anything is saved on it.
    await pump(model('qwen3-30b-a3b-thinking-2507', thinking: false));
    expect(find.text('on'), findsNWidgets(2));
    expect(find.text('off'), findsNothing);
    await pump(model('qwen3-30b-a3b-instruct-2507', thinking: true));
    expect(find.text('off'), findsNWidgets(2));
    expect(find.text('on'), findsNothing);
    // A hybrid family follows the saved choice — off on the new route, where
    // nothing is saved.
    await pump(model('qwen3-32b', thinking: true));
    expect(find.text('on'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);
  });

  testWidgets('a platform field is named with the choice the request carries', (
    tester,
  ) async {
    // DashScope's `enable_thinking` goes out both ways with the resolved
    // choice; the new route's request carries one before anything is saved
    // on it.
    useTempSupportDir();
    AiModelEntry model(String upstream, {required bool thinking}) =>
        AiModelEntry.create(
          upstream: upstream,
          route: AiProviderType.openAi,
        ).copyWith(
          params: {
            AiProviderType.openAi: RouteParams(thinkingEnabled: thinking),
          },
        );
    Future<void> pump(AiModelEntry m) => pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel:
            AiChannel.create(
              platform: PlatformProfiles.dashScope,
              name: 'd',
              apiKey: 'k-dialog-dashscope',
            ).copyWith(
              routes: const [
                AiRoute(protocol: AiProviderType.openAi),
                AiRoute(protocol: AiProviderType.anthropic),
              ],
              models: [m],
            ),
        model: m,
        to: AiProviderType.anthropic,
      ),
      profiles: AiProfilesService(),
    );

    await pump(model('qwen3-30b-a3b-thinking-2507', thinking: false));
    expect(find.text('on · enable_thinking'), findsOneWidget);
    // The Messages route it would switch to asks on too, with nothing saved,
    // in its own field: DashScope's Messages face is a switch as well.
    expect(find.text('on · thinking'), findsOneWidget);
    await pump(model('qwen3-30b-a3b-instruct-2507', thinking: true));
    expect(find.text('off · enable_thinking'), findsOneWidget);
    expect(find.text('off · thinking'), findsOneWidget);
  });
}
