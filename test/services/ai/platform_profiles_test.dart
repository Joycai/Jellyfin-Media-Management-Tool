import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/services/ai/thinking_dialect.dart';

AiConfig _at(String endpoint, {String? platform}) => AiConfig(
  provider: AiProviderType.openAi,
  endpoint: endpoint,
  apiKey: 'k',
  model: 'm',
  platform: platform,
);

void main() {
  test('platforms are recognised by host, subdomains included', () {
    expect(
      PlatformProfiles.forHost('https://open.bigmodel.cn/api/paas/v4')?.id,
      'zhipu',
    );
    expect(
      PlatformProfiles.forHost('https://api.deepseek.com')?.id,
      'deepseek',
    );
    for (final host in ['dashscope', 'dashscope-intl', 'dashscope-us']) {
      expect(
        PlatformProfiles.forHost(
          'https://$host.aliyuncs.com/compatible-mode',
        )?.id,
        'dashscope',
      );
    }
  });

  test('a look-alike host is no platform', () {
    expect(PlatformProfiles.forHost('https://notbigmodel.cn'), isNull);
    expect(PlatformProfiles.forHost('https://oss.aliyuncs.com'), isNull);
    expect(PlatformProfiles.forHost('http://localhost:1234'), isNull);
    expect(PlatformProfiles.forHost(''), isNull);
  });

  test('the reasoning switch comes from the platform, not the model name', () {
    expect(
      PlatformProfiles.dialectFor(_at('https://open.bigmodel.cn/api/paas/v4')),
      ThinkingDialect.thinkingType,
    );
    expect(
      PlatformProfiles.dialectFor(
        _at('https://dashscope.aliyuncs.com/compatible-mode/v1'),
      ),
      ThinkingDialect.enableThinking,
    );
    // A relay on its own host gets OpenRouter's switch only when the channel
    // says it is OpenRouter.
    expect(
      PlatformProfiles.dialectFor(
        _at('https://my-router.example/api/v1', platform: 'openrouter'),
      ),
      ThinkingDialect.reasoningObject,
    );
    expect(PlatformProfiles.dialectFor(_at('http://localhost:1234')), isNull);
  });

  test('every profile is well formed', () {
    final ids = <String>{};
    for (final profile in PlatformProfiles.all) {
      expect(ids.add(profile.id), isTrue, reason: 'duplicate ${profile.id}');
      expect(profile.routes, isNotEmpty, reason: profile.id);
      for (final spec in profile.routes.values) {
        expect(spec.source, isNotEmpty, reason: profile.id);
        expect(
          spec.defaultPath.isEmpty || spec.defaultPath.startsWith('/'),
          isTrue,
          reason: '${profile.id} ${spec.defaultPath}',
        );
      }
      if (profile.kind == PlatformKind.vendor) {
        expect(profile.hosts, isNotEmpty, reason: profile.id);
        expect(profile.needsKey, isTrue, reason: profile.id);
      }
    }
    expect(PlatformProfiles.byId('nope'), PlatformProfiles.custom);
  });

  test('whose server a route talks to is declared or in the address', () {
    // A local platform's profile names software, not whose machine: at its
    // own address the user's, at a public name (Ollama's hosted API) unknown.
    for (final id in ['lmstudio', 'ollama', 'llamacpp']) {
      expect(
        PlatformProfiles.serverOwner(
          _at('http://localhost:1234', platform: id),
        ),
        ServerOwner.own,
        reason: id,
      );
      expect(
        PlatformProfiles.serverOwner(_at('https://ollama.com', platform: id)),
        ServerOwner.unknown,
        reason: id,
      );
    }
    // This computer or a private network, by the names and address blocks
    // reserved for it — whatever answers there. A vendor's or a relay's
    // profile at such an address disagrees with it (a proxy in front of a
    // cloud, or the user's own server under that profile): unknown.
    const private = [
      'http://localhost:8080',
      'http://box.localhost:8080',
      'http://mac.local:8080/v1',
      'http://llm.internal:8080',
      'http://box.home.arpa:8080',
      'http://127.0.0.1:8000',
      'http://127.5.5.5:8000',
      'http://0.0.0.0:8080',
      'http://[::1]:8080/v1',
      'http://[::]:8080',
      'http://[::ffff:192.168.1.1]:1234',
      'http://[::ffff:127.0.0.1]:1234',
      'http://[::ffff:169.254.1.1]:1234',
      'http://[::ffff:0.0.0.0]:1234',
      'http://192.168.1.5:1234',
      'http://10.0.0.7:11434',
      'http://100.64.0.1:11434',
      'http://100.127.255.254:11434',
      'http://172.16.2.2:1234',
      'http://172.31.2.2:1234',
      'http://[fd00::5]:1234',
      'http://[fc00::1]:1234',
      'http://[fe80::1]:1234',
      'http://[febf::1]:1234',
      'http://169.254.1.1:1234',
    ];
    for (final endpoint in private) {
      expect(PlatformProfiles.privateHost(endpoint), isTrue, reason: endpoint);
      expect(PlatformProfiles.of(_at(endpoint)).kind, PlatformKind.custom);
      expect(PlatformProfiles.serverOwner(_at(endpoint)), ServerOwner.own);
      for (final id in ['custom', 'lmstudio']) {
        expect(
          PlatformProfiles.serverOwner(_at(endpoint, platform: id)),
          ServerOwner.own,
          reason: '$endpoint $id',
        );
      }
      for (final id in ['relay', 'deepseek', 'openai']) {
        expect(
          PlatformProfiles.serverOwner(_at(endpoint, platform: id)),
          ServerOwner.unknown,
          reason: '$endpoint $id',
        );
      }
    }
    // A public name says nothing — not a house's `.lan`, not a tailnet's
    // name — so a custom channel there is not known either way.
    const public = [
      'https://llm.example.com',
      'https://llm.example.lan.com',
      'http://nas.lan:8080',
      'http://studio.tail1234.ts.net:1234',
      'http://203.0.113.5:1234',
      'http://[::ffff:203.0.113.5]:1234',
      'http://192.169.0.1:1234',
      'http://192.0.2.1:1234',
      'http://169.253.0.1:1234',
      'http://169.60.0.1:1234',
      'http://172.15.0.1:1234',
      'http://172.32.0.1:1234',
      'http://100.63.0.1:1234',
      'http://100.128.0.1:1234',
      'http://[2001:db8::1]:1234',
      'http://[fe00::1]:1234',
      'http://[fec0::1]:1234',
      'http://[fe00::ffff:127.0.0.1]:1234',
    ];
    for (final endpoint in public) {
      expect(PlatformProfiles.privateHost(endpoint), isFalse, reason: endpoint);
      expect(
        PlatformProfiles.serverOwner(_at(endpoint)),
        ServerOwner.unknown,
        reason: endpoint,
      );
      expect(
        PlatformProfiles.serverOwner(_at(endpoint, platform: 'custom')),
        ServerOwner.unknown,
        reason: endpoint,
      );
      // A vendor's, or a relay's, is someone else's.
      expect(
        PlatformProfiles.serverOwner(_at(endpoint, platform: 'relay')),
        ServerOwner.other,
        reason: endpoint,
      );
      expect(
        PlatformProfiles.serverOwner(_at(endpoint, platform: 'openai')),
        ServerOwner.other,
        reason: endpoint,
      );
    }
    for (final endpoint in [
      'https://api.deepseek.com',
      'https://open.bigmodel.cn/api/paas/v4',
    ]) {
      expect(PlatformProfiles.serverOwner(_at(endpoint)), ServerOwner.other);
    }
  });

  test('only MiniMax declares a Messages thinking switch', () {
    // MiniMax-M3's /anthropic takes `adaptive | disabled` only (KB 03 §3).
    for (final profile in PlatformProfiles.all) {
      final spec = profile.routes[AiProviderType.anthropic];
      if (spec == null) continue;
      expect(
        spec.messagesThinkingSwitch,
        profile.id == 'minimax',
        reason: profile.id,
      );
    }
    AiConfig messages(String endpoint) => AiConfig(
      provider: AiProviderType.anthropic,
      endpoint: endpoint,
      apiKey: 'k',
      model: 'm',
    );
    expect(
      PlatformProfiles.messagesSwitchFor(
        messages('https://api.minimaxi.com/anthropic'),
      ),
      isTrue,
    );
    // The same host on Chat Completions has no such switch.
    expect(
      PlatformProfiles.messagesSwitchFor(_at('https://api.minimaxi.com/v1')),
      isFalse,
    );
    expect(
      PlatformProfiles.messagesSwitchFor(
        messages('https://open.bigmodel.cn/api/anthropic'),
      ),
      isFalse,
    );
  });

  group('reasoningRouteFor', () {
    AiConfig at(
      AiProviderType provider,
      String endpoint,
      String model, {
      bool thinking = false,
    }) => AiConfig(
      provider: provider,
      endpoint: endpoint,
      apiKey: 'k',
      model: model,
      thinkingEnabled: thinking,
    );
    const zhipu = 'https://open.bigmodel.cn/api/paas/v4';
    const miniMax = 'https://api.minimaxi.com/anthropic';
    const relay = 'https://relay.example.com';

    ({ReasoningRoute route, String? field}) read(
      AiConfig config, {
      Set<String> rejected = const {},
      Set<String> tried = const {},
    }) => PlatformProfiles.reasoningRouteFor(
      config,
      LearnedBehaviour(rejectedFields: rejected, thinkingOffTried: tried),
    );

    test('Chat Completions: the platform dialect, or the ladder', () {
      final glm = at(AiProviderType.openAi, zhipu, 'glm-5.3');
      expect(read(glm), (
        route: ReasoningRoute.platformField,
        field: 'thinking',
      ));
      expect(read(glm, tried: {LearnedBehaviour.dialectOff}), (
        route: ReasoningRoute.offRefused,
        field: 'thinking',
      ));
      expect(read(glm, rejected: {'thinking'}), (
        route: ReasoningRoute.refused,
        field: 'thinking',
      ));
      // "Always reasons" says more than the refused name.
      expect(
        read(
          glm,
          rejected: {'thinking'},
          tried: {LearnedBehaviour.dialectOff},
        ).route,
        ReasoningRoute.offRefused,
      );
      // Another field refused leaves the switch alone.
      expect(
        read(glm, rejected: {'top_k'}).route,
        ReasoningRoute.platformField,
      );

      final local = at(AiProviderType.openAi, 'http://localhost:1234', 'm');
      expect(read(local), (route: ReasoningRoute.ladder, field: null));
      // A switch refused under another platform is no switch here.
      expect(
        read(local, tried: {LearnedBehaviour.dialectOff}).route,
        ReasoningRoute.ladder,
      );
    });

    test('Gemini has only the ladder', () {
      expect(read(at(AiProviderType.googleGenAi, relay, 'gemini-3-pro')), (
        route: ReasoningRoute.ladder,
        field: null,
      ));
    });

    test('Messages: a switch route, or the protocol field', () {
      final m3 = at(AiProviderType.anthropic, miniMax, 'MiniMax-M3');
      expect(read(m3), (
        route: ReasoningRoute.platformField,
        field: 'thinking',
      ));
      expect(read(m3, tried: {LearnedBehaviour.dialectOff}), (
        route: ReasoningRoute.offRefused,
        field: 'thinking',
      ));
      // A switch route asks adaptive only; refused, on is not sent.
      expect(read(m3, rejected: {'thinking:adaptive'}), (
        route: ReasoningRoute.onRefused,
        field: 'thinking',
      ));
      expect(
        read(m3, rejected: {'thinking:enabled'}).route,
        ReasoningRoute.platformField,
      );
      // The field itself refused — a server that does not know it — is
      // sent neither way; a model that said it cannot stop outranks it.
      expect(
        read(
          m3,
          rejected: {'thinking', 'thinking:adaptive', 'thinking:enabled'},
        ),
        (route: ReasoningRoute.refused, field: 'thinking'),
      );
      expect(
        read(
          m3,
          rejected: {'thinking', 'thinking:adaptive', 'thinking:enabled'},
          tried: {LearnedBehaviour.dialectOff},
        ).route,
        ReasoningRoute.offRefused,
      );

      final claude = at(AiProviderType.anthropic, relay, 'claude-sonnet-4-5');
      expect(read(claude), (
        route: ReasoningRoute.protocolField,
        field: 'thinking',
      ));
      // One form refused: the other is still asked.
      expect(
        read(claude, rejected: {'thinking:enabled'}).route,
        ReasoningRoute.protocolField,
      );
      // Every form refused: nothing either way, and off is the default.
      expect(
        read(claude, rejected: {'thinking:adaptive', 'thinking:enabled'}),
        (route: ReasoningRoute.refused, field: 'thinking'),
      );
      // A bare legacy record where `enabled` is the model's first form.
      expect(read(claude, rejected: {'thinking'}), (
        route: ReasoningRoute.refused,
        field: 'thinking',
      ));
      // Where adaptive comes first, the same record is no verdict on it: the
      // model's own first form decides.
      expect(
        read(
          at(AiProviderType.anthropic, relay, 'claude-sonnet-4-6'),
          rejected: {'thinking'},
        ).route,
        ReasoningRoute.protocolField,
      );
      // Off is the protocol's default there: nothing to refuse.
      expect(
        read(claude, tried: {LearnedBehaviour.dialectOff}).route,
        ReasoningRoute.protocolField,
      );
    });

    test('Responses: reasoning.effort, until refused', () {
      final grok = at(AiProviderType.openAiResponses, relay, 'grok-4.5');
      expect(read(grok), (
        route: ReasoningRoute.protocolField,
        field: 'reasoning.effort',
      ));
      // Refused none: a model that always reasons and one that cannot
      // reason are refused alike.
      expect(read(grok, tried: {LearnedBehaviour.effortNone}), (
        route: ReasoningRoute.offToDefault,
        field: 'reasoning.effort',
      ));
      expect(read(grok, rejected: {'reasoning'}), (
        route: ReasoningRoute.refused,
        field: 'reasoning.effort',
      ));
      // Another field refused: `reasoning` is still sent both ways.
      expect(
        read(grok, rejected: {'include'}).route,
        ReasoningRoute.protocolField,
      );
      // Refused by name as well: nothing either way.
      expect(
        read(
          grok,
          rejected: {'reasoning'},
          tried: {LearnedBehaviour.effortNone},
        ).route,
        ReasoningRoute.refused,
      );
    });

    test('what a toggle does, and is drawn as', () {
      expect(
        [
          for (final r in ReasoningRoute.values)
            if (r.switchable) r,
        ],
        [
          ReasoningRoute.platformField,
          ReasoningRoute.protocolField,
          // Off is still sent, so the toggle can still turn reasoning off.
          ReasoningRoute.onRefused,
          // On is still sent; what off does, only a test shows.
          ReasoningRoute.offToDefault,
        ],
      );
      expect(ReasoningRoute.offRefused.drawnAs, isTrue);
      expect(ReasoningRoute.refused.drawnAs, isFalse);
      for (final free in [
        ReasoningRoute.platformField,
        ReasoningRoute.protocolField,
        ReasoningRoute.onRefused,
        ReasoningRoute.offToDefault,
        ReasoningRoute.ladder,
      ]) {
        expect(free.drawnAs, isNull, reason: '$free');
      }
    });

    // The adapters read the same memory on their own; what each state says
    // the toggle does is held against the body they would send.
    group('agrees with what the adapters send', () {
      Future<void> check(
        AiConfig Function({bool thinking}) make, {
        required String base,
        required String wire,
        required ReasoningRoute expected,
        Set<String> rejected = const {},
        Set<String> tried = const {},
      }) async {
        final learned = LearnedBehaviour(
          rejectedFields: rejected,
          thinkingOffTried: tried,
        );
        final config = make();
        final key = LearnedStore.routeKey(
          protocol: config.provider.id,
          base: base,
          model: config.model,
          apiKey: config.apiKey,
        );
        final on = AiService.providerFor(make(thinking: true));
        final off = AiService.providerFor(config);
        addTearDown(on.forgetLearned);
        LearnedStore.instance.update(
          key,
          (b) => b.copyWith(rejectedFields: rejected, thinkingOffTried: tried),
        );
        expect(
          off.learned.sameAs(learned),
          isTrue,
          reason: 'the test wrote the route the adapter reads',
        );

        Future<Object?> sent(AiProvider provider) async =>
            (await provider.previewRequest(
              messages: const [UserMessage('u')],
              tools: const [],
            ))!.body[wire];
        final whenOn = await sent(on);
        final whenOff = await sent(off);

        final route = PlatformProfiles.reasoningRouteFor(config, learned).route;
        expect(route, expected);
        // A live toggle changes the body. The converse does not hold: with
        // off refused the two bodies differ, but the model reasons in both.
        if (route.switchable) {
          expect(
            whenOn,
            isNot(whenOff),
            reason: 'a live toggle does something',
          );
        }
        switch (route) {
          case ReasoningRoute.offRefused:
            // On is still sent, unless the field was refused by name too.
            if (rejected.isEmpty) {
              expect(whenOn, isNotNull, reason: 'on is still sent');
            }
            expect(whenOff, isNull);
          case ReasoningRoute.offToDefault:
            expect(whenOn, isNotNull, reason: 'on is still sent');
            expect(whenOff, isNull);
          case ReasoningRoute.onRefused:
            expect(whenOn, isNull);
          case ReasoningRoute.refused:
            expect(whenOn, isNull);
            expect(whenOff, isNull);
          case ReasoningRoute.platformField:
            expect(whenOn, isNotNull);
            expect(whenOff, isNotNull);
          case ReasoningRoute.protocolField:
            expect(whenOn, isNotNull);
          case ReasoningRoute.ladder:
            fail('no field to hold against');
        }
      }

      test('Chat Completions with a dialect', () async {
        AiConfig glm({bool thinking = false}) =>
            at(AiProviderType.openAi, zhipu, 'glm-5.3', thinking: thinking);
        for (final (rejected, tried, expected) in [
          (<String>{}, <String>{}, ReasoningRoute.platformField),
          (
            <String>{},
            {LearnedBehaviour.dialectOff},
            ReasoningRoute.offRefused,
          ),
          ({'thinking'}, <String>{}, ReasoningRoute.refused),
          (
            {'thinking'},
            {LearnedBehaviour.dialectOff},
            ReasoningRoute.offRefused,
          ),
        ]) {
          await check(
            glm,
            base: zhipu,
            wire: 'thinking',
            expected: expected,
            rejected: rejected,
            tried: tried,
          );
        }
      });

      test('Messages', () async {
        AiConfig m3({bool thinking = false}) => at(
          AiProviderType.anthropic,
          miniMax,
          'MiniMax-M3',
          thinking: thinking,
        );
        for (final (rejected, tried, expected) in [
          (<String>{}, <String>{}, ReasoningRoute.platformField),
          (
            <String>{},
            {LearnedBehaviour.dialectOff},
            ReasoningRoute.offRefused,
          ),
          ({'thinking:adaptive'}, <String>{}, ReasoningRoute.onRefused),
          (
            {'thinking:adaptive'},
            {LearnedBehaviour.dialectOff},
            ReasoningRoute.offRefused,
          ),
          // A legacy bare record is read against the form asked first:
          // adaptive here, though the model's own would be extended.
          ({'thinking'}, <String>{}, ReasoningRoute.platformField),
          // The field itself refused: nothing either way.
          (
            {'thinking', 'thinking:adaptive', 'thinking:enabled'},
            <String>{},
            ReasoningRoute.refused,
          ),
          // Every form is the field, with or without the bare name.
          (
            {'thinking:adaptive', 'thinking:enabled'},
            <String>{},
            ReasoningRoute.refused,
          ),
          // A bare record beside a form is read by the forms alone.
          (
            {'thinking', 'thinking:adaptive'},
            <String>{},
            ReasoningRoute.onRefused,
          ),
          // The model said it cannot stop, and later the field was refused
          // too: nothing is sent, and the model's word stands.
          (
            {'thinking', 'thinking:adaptive', 'thinking:enabled'},
            {LearnedBehaviour.dialectOff},
            ReasoningRoute.offRefused,
          ),
        ]) {
          await check(
            m3,
            base: '$miniMax/v1',
            wire: 'thinking',
            expected: expected,
            rejected: rejected,
            tried: tried,
          );
        }
        AiConfig claude({bool thinking = false}) => at(
          AiProviderType.anthropic,
          relay,
          'claude-sonnet-4-5',
          thinking: thinking,
        );
        for (final (rejected, expected) in [
          (<String>{}, ReasoningRoute.protocolField),
          ({'thinking:adaptive', 'thinking:enabled'}, ReasoningRoute.refused),
          // A legacy bare record, against the extended this model asks first.
          ({'thinking'}, ReasoningRoute.refused),
        ]) {
          await check(
            claude,
            base: '$relay/v1',
            wire: 'thinking',
            expected: expected,
            rejected: rejected,
          );
        }
        // Against adaptive, a bare record reads as extended refused, so
        // adaptive is still asked.
        AiConfig claude46({bool thinking = false}) => at(
          AiProviderType.anthropic,
          relay,
          'claude-sonnet-4-6',
          thinking: thinking,
        );
        await check(
          claude46,
          base: '$relay/v1',
          wire: 'thinking',
          expected: ReasoningRoute.protocolField,
          rejected: {'thinking'},
        );
      });

      test('Responses', () async {
        AiConfig grok({bool thinking = false}) => at(
          AiProviderType.openAiResponses,
          relay,
          'grok-4.5',
          thinking: thinking,
        );
        for (final (rejected, tried, expected) in [
          (<String>{}, <String>{}, ReasoningRoute.protocolField),
          (
            <String>{},
            {LearnedBehaviour.effortNone},
            ReasoningRoute.offToDefault,
          ),
          ({'reasoning'}, <String>{}, ReasoningRoute.refused),
          (
            {'reasoning'},
            {LearnedBehaviour.effortNone},
            ReasoningRoute.refused,
          ),
        ]) {
          await check(
            grok,
            base: '$relay/v1',
            wire: 'reasoning',
            expected: expected,
            rejected: rejected,
            tried: tried,
          );
        }
      });
    });

    // What each body says about reasoning is what the adapter sends before
    // any refusal; every adapter reads `AiConfig.sampling.thinking`.
    test('every protocol asks for reasoning as the family runs', () async {
      // The saved choice is read once, above the adapters
      // (`AiConfig.sampling.thinking`): a family that always or never
      // reasons is sent as it runs, the other families and a model no
      // preset knows as saved. Each protocol's body is held to that value.
      Future<Map<String, dynamic>> body(AiConfig config) async =>
          (await AiService.providerFor(config).previewRequest(
            messages: const [SystemMessage('s'), UserMessage('u')],
            tools: const [],
          ))!.body;
      // One family of each kind, and a model no preset knows.
      const models = {
        'mystery-model': null,
        'qwen3-30b-a3b-instruct-2507': ThinkingControl.none,
        'qwen3.5-9b': ThinkingControl.templateSwitch,
        'qwen3-32b': ThinkingControl.softSwitch,
        'gemma4-26b': ThinkingControl.promptToken,
        'qwen3-30b-a3b-thinking-2507': ThinkingControl.alwaysOn,
        'gpt-oss-20b': ThinkingControl.effortOnly,
      };
      for (final MapEntry(key: model, value: control) in models.entries) {
        expect(SamplingPresets.forModel(model)?.thinkingControl, control);
        for (final saved in [true, false]) {
          final asked = at(
            AiProviderType.openAi,
            zhipu,
            model,
            thinking: saved,
          ).sampling.thinking;
          expect(asked, switch (control) {
            ThinkingControl.none => false,
            ThinkingControl.alwaysOn || ThinkingControl.effortOnly => true,
            _ => saved,
          }, reason: '$model saved $saved');
          final why = '$model saved $saved';

          // Chat Completions: the platform's field carries it, whichever
          // field the platform takes.
          final chat = at(AiProviderType.openAi, zhipu, model, thinking: saved);
          final chatBody = await body(chat);
          expect(
            (chatBody['thinking'] as Map)['type'] == 'enabled',
            asked,
            reason: 'chat $why',
          );
          // The platform's switch is the whole request for reasoning there:
          // no effort level beside it, the least included.
          expect(
            chatBody.containsKey('reasoning_effort'),
            isFalse,
            reason: 'chat $why',
          );
          final dashScope = at(
            AiProviderType.openAi,
            'https://dashscope.aliyuncs.com/compatible-mode/v1',
            model,
            thinking: saved,
          );
          expect(
            (await body(dashScope))['enable_thinking'],
            asked,
            reason: 'dashscope $why',
          );
          // The ladder has nothing to send for on: it asks off only where
          // the family can be switched.
          final local = at(
            AiProviderType.openAi,
            'http://localhost:1234',
            model,
            thinking: saved,
          );
          final localBody = await body(local);
          expect(
            localBody.containsKey('chat_template_kwargs'),
            !asked &&
                (control == ThinkingControl.softSwitch ||
                    control == ThinkingControl.templateSwitch),
            reason: 'local $why',
          );
          // A family that can only be lowered gets the least, whatever was
          // saved; Gemma 4 reasons only behind its prompt token.
          expect(
            localBody['reasoning_effort'] == 'low',
            control == ThinkingControl.effortOnly,
            reason: 'local $why',
          );
          if (control == ThinkingControl.promptToken) {
            final system =
                ((localBody['messages'] as List).first as Map)['content']
                    as String;
            expect(system.startsWith('<|think|>'), asked, reason: 'local $why');
          }

          // Messages: `thinking` only when on; a switch route says off too.
          final messages = at(
            AiProviderType.anthropic,
            relay,
            model,
            thinking: saved,
          );
          expect(
            (await body(messages)).containsKey('thinking'),
            asked,
            reason: 'messages $why',
          );
          final switchRoute = at(
            AiProviderType.anthropic,
            miniMax,
            model,
            thinking: saved,
          );
          expect(
            ((await body(switchRoute))['thinking'] as Map)['type'],
            asked ? 'adaptive' : 'disabled',
            reason: 'switch $why',
          );

          // Responses: an effort both ways; a family that cannot stop gets
          // the least.
          final responses = at(
            AiProviderType.openAiResponses,
            relay,
            model,
            thinking: saved,
          );
          final effort =
              ((await body(responses))['reasoning'] as Map)['effort'];
          expect(effort != 'none', asked, reason: 'responses $why');
          expect(
            effort == 'low',
            control == ThinkingControl.effortOnly,
            reason: 'responses $why',
          );

          // Gemini: off is asked through thinkingConfig, on is the default.
          final gemini = at(
            AiProviderType.googleGenAi,
            'https://g.example',
            model,
            thinking: saved,
          );
          expect(
            !((await body(gemini))['generationConfig'] as Map).containsKey(
              'thinkingConfig',
            ),
            asked,
            reason: 'gemini $why',
          );
        }
      }
    });
  });
}
