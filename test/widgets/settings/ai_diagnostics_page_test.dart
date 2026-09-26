import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations_en.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_diagnostics_page.dart';

import '../../helpers/settings.dart';

void main() {
  testWidgets("today's API log is listed, newest first", (tester) async {
    useTempSupportDir();
    final dir = Directory.systemTemp.createTempSync('diag_log');
    addTearDown(() {
      ApiLog.instance
        ..enabled = false
        ..directory = null;
      dir.deleteSync(recursive: true);
    });
    ApiLog.instance
      ..directory = dir
      ..enabled = true;
    await tester.runAsync(() async {
      for (final model in ['first-model', 'second-model']) {
        ApiLog.instance.record(
          protocol: 'chat',
          model: model,
          url: Uri.parse('http://x/v1/chat/completions'),
          request: const {},
          status: 200,
          response: const {
            'finish_reason': 'stop',
            'usage': {'prompt': 10, 'completion': 2},
          },
        );
      }
      await ApiLog.instance.flush();
    });

    await pumpAiPage(
      tester,
      AiDiagnosticsPage(initialModelId: null, onBack: () {}),
      profiles: AiProfilesService(),
    );
    // The page reads the log from disk, which only real time moves along.
    for (
      var i = 0;
      i < 10 && find.textContaining('first-model').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.textContaining('first-model'));
    final second = tester.getTopLeft(find.textContaining('second-model'));
    expect(second.dy, lessThan(first.dy));
    await settleSaves(tester);
  });

  test('the reasoning step is judged by the reply, whichever way', () {
    final l10n = AppLocalizationsEn();
    expect(thinkingStep(l10n, asked: false, reasoned: false), (
      ok: true,
      text: l10n.aiStepThinkingOff,
    ));
    expect(thinkingStep(l10n, asked: false, reasoned: true), (
      ok: false,
      text: l10n.aiStepThinkingStillOn,
    ));
    expect(thinkingStep(l10n, asked: true, reasoned: true), (
      ok: true,
      text: l10n.aiStepThinkingOn,
    ));
    // A relay that drops the request for thinking says nothing — but an
    // adaptive model may also skip thinking on a request this small, so it
    // is undecided rather than failed.
    expect(thinkingStep(l10n, asked: true, reasoned: false), (
      ok: null,
      text: l10n.aiStepThinkingNotOn,
    ));
    // Refused during the test, and no longer sent: not an open question.
    expect(thinkingStep(l10n, asked: true, reasoned: false, refused: true), (
      ok: false,
      text: l10n.aiStepThinkingRefused,
    ));
    // Off sends nothing on this route: reasoning is the model's default,
    // not a failure the user can switch away.
    expect(thinkingStep(l10n, asked: false, reasoned: true, cannotStop: true), (
      ok: null,
      text: l10n.aiStepThinkingCannotStop,
    ));
    expect(
      thinkingStep(l10n, asked: false, reasoned: false, cannotStop: true),
      (ok: true, text: l10n.aiStepThinkingOff),
    );
  });

  test('the step is judged against what the test sent', () {
    final l10n = AppLocalizationsEn();
    ({bool? ok, String text}) step(
      AiProviderType provider,
      String endpoint,
      String model, {
      required bool saved,
      required bool reasoned,
      Set<String> rejected = const {},
      Set<String> tried = const {},
    }) => reasoningStepFor(
      l10n,
      AiConfig(
        provider: provider,
        endpoint: endpoint,
        apiKey: 'k',
        model: model,
        thinkingEnabled: saved,
      ),
      LearnedBehaviour(rejectedFields: rejected, thinkingOffTried: tried),
      reasoned: reasoned,
    );
    const responses = AiProviderType.openAiResponses;

    // Asked for, refused by name, and the model reasoned at its default
    // anyway: the reply is what counts.
    expect(
      step(
        responses,
        'https://r.io',
        'grok-4.5',
        saved: true,
        reasoned: true,
        rejected: {'reasoning'},
      ),
      (ok: true, text: l10n.aiStepThinkingOn),
    );
    // Refused with no reply reasoning: a model no preset knows is locked
    // there, with the saved "on" nothing can change — said, not failed.
    expect(
      step(
        responses,
        'https://r.io',
        'grok-4.5',
        saved: true,
        reasoned: false,
        rejected: {'reasoning'},
      ),
      (ok: null, text: l10n.aiStepThinkingRefused),
    );
    // A preset family's toggle stays live, so the user can turn it off.
    expect(
      step(
        responses,
        'https://r.io',
        'qwen3-32b',
        saved: true,
        reasoned: false,
        rejected: {'reasoning'},
      ),
      (ok: false, text: l10n.aiStepThinkingRefused),
    );
    // So does a switch route that refused only on.
    expect(
      step(
        AiProviderType.anthropic,
        'https://api.minimaxi.com/anthropic',
        'MiniMax-M3',
        saved: true,
        reasoned: false,
        rejected: {'thinking:adaptive'},
      ),
      (ok: false, text: l10n.aiStepThinkingRefused),
    );

    // Off sent, and refused by a model that cannot stop: reasoning is its
    // default, and none shown is still off.
    for (final (reasoned, expected) in [
      (true, (ok: null, text: l10n.aiStepThinkingCannotStop)),
      (false, (ok: true, text: l10n.aiStepThinkingOff)),
    ]) {
      expect(
        step(
          AiProviderType.openAi,
          'https://open.bigmodel.cn/api/paas/v4',
          'glm-5.3',
          saved: false,
          reasoned: reasoned,
          tried: {LearnedBehaviour.dialectOff},
        ),
        expected,
      );
    }
  });

  test('the step reads the route as the model page does', () {
    AiConfig config(AiProviderType provider, String endpoint, String model) =>
        AiConfig(
          provider: provider,
          endpoint: endpoint,
          apiKey: 'k',
          model: model,
          thinkingEnabled: true,
        );
    ReasoningRoute route(
      AiConfig config, {
      Set<String> rejected = const {},
      Set<String> tried = const {},
    }) => PlatformProfiles.reasoningRouteFor(
      config,
      LearnedBehaviour(rejectedFields: rejected, thinkingOffTried: tried),
    ).route;

    final messages = config(
      AiProviderType.anthropic,
      'https://a.example',
      'claude-sonnet-4-5',
    );
    // A refused form alone is not a refused request: the other is tried.
    expect(
      reasoningRefused(route(messages, rejected: {'thinking:adaptive'})),
      isFalse,
    );
    // Both forms refused by name, with no bare `thinking` beside them.
    expect(
      reasoningRefused(
        route(messages, rejected: {'thinking:adaptive', 'thinking:enabled'}),
      ),
      isTrue,
    );
    // A switch route asks adaptive only.
    final m3 = config(
      AiProviderType.anthropic,
      'https://api.minimaxi.com/anthropic',
      'MiniMax-M3',
    );
    expect(
      reasoningRefused(route(m3, rejected: {'thinking:adaptive'})),
      isTrue,
    );
    expect(
      reasoningCannotStop(route(m3, tried: {LearnedBehaviour.dialectOff})),
      isTrue,
    );

    final responses = config(
      AiProviderType.openAiResponses,
      'https://r.io',
      'grok-4.5',
    );
    expect(reasoningRefused(route(responses, rejected: {'include'})), isFalse);
    expect(reasoningRefused(route(responses, rejected: {'reasoning'})), isTrue);
    expect(
      reasoningCannotStop(
        route(responses, tried: {LearnedBehaviour.effortNone}),
      ),
      isTrue,
    );
    // Refused both ways: the model page warns that it still reasons, so this
    // is a failed step, not the model's own default.
    expect(
      reasoningCannotStop(
        route(
          responses,
          rejected: {'reasoning'},
          tried: {LearnedBehaviour.effortNone},
        ),
      ),
      isFalse,
    );

    // Chat Completions: the platform's switch, and nothing without one.
    final zhipu = config(
      AiProviderType.openAi,
      'https://open.bigmodel.cn/api/paas/v4',
      'glm-5.3',
    );
    expect(reasoningRefused(route(zhipu, rejected: {'thinking'})), isTrue);
    expect(reasoningCannotStop(route(zhipu, rejected: {'thinking'})), isFalse);
    expect(reasoningRefused(route(zhipu, rejected: {'top_k'})), isFalse);
    expect(
      reasoningCannotStop(route(zhipu, tried: {LearnedBehaviour.dialectOff})),
      isTrue,
    );
    final local = config(AiProviderType.openAi, 'http://localhost:1234', 'm');
    expect(reasoningRefused(route(local, rejected: {'thinking'})), isFalse);
    expect(reasoningCannotStop(route(local)), isFalse);
    final gemini = config(
      AiProviderType.googleGenAi,
      'https://g.example',
      'gemini-3-pro',
    );
    expect(
      reasoningRefused(route(gemini, rejected: {'thinkingConfig'})),
      isFalse,
    );
  });
}
