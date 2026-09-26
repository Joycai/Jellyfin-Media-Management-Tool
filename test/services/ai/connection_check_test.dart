import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/anthropic_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/connection_check.dart';
import 'package:jellyfin_media_management_tool/services/ai/google_genai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_responses_provider.dart';

import '../../helpers/ai.dart';

void main() {
  group('AiConfig.isComplete', () {
    const local = AiConfig(
      provider: AiProviderType.openAi,
      endpoint: 'http://localhost:1234/v1',
      apiKey: '',
      model: 'qwen/qwen3-8b',
    );

    test('an OpenAI-compatible server needs no key', () {
      expect(local.isComplete, isTrue);
    });

    test('Google does', () {
      const google = AiConfig(
        provider: AiProviderType.googleGenAi,
        endpoint: 'https://generativelanguage.googleapis.com',
        apiKey: '',
        model: 'gemini-2.0-flash',
      );
      expect(google.isComplete, isFalse);
    });

    test('token counts survive a round trip; junk means unset', () {
      const budgeted = AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'http://localhost:1234/v1',
        apiKey: '',
        model: 'm',
        contextWindow: 8192,
        maxOutputTokens: 2048,
      );
      final restored = AiConfig.fromJson(budgeted.toJson());
      expect(restored.contextWindow, 8192);
      expect(restored.maxOutputTokens, 2048);

      expect(AiConfig.tokenCount(' 4096 '), 4096);
      expect(AiConfig.tokenCount('0'), isNull);
      expect(AiConfig.tokenCount(-1), isNull);
      expect(AiConfig.tokenCount('abc'), isNull);
      expect(AiConfig.tokenCount(null), isNull);
    });
  });

  group('AiConnectionCheck', () {
    test('asks for the greeting as a tool call, as tasks do', () async {
      final provider = ScriptedChatProvider([
        (_) => const ChatResult(
          toolCalls: [
            ToolCall(
              id: 'c0',
              name: 'report_greeting',
              arguments: '{"greeting": " Hi! "}',
            ),
          ],
        ),
      ]);

      final result = await AiConnectionCheck.run(provider);

      expect(provider.calls, 1);
      expect(provider.offeredTools.single, ['report_greeting']);
      expect(result.supportsTools, ToolProbe.supported);
      expect(result.reply, 'Hi!');
    });

    test('a server that refuses tools still proves it answers', () async {
      var chats = 0;
      final provider = _RefusesTools(() => chats++);

      final result = await AiConnectionCheck.run(provider);

      expect(chats, 1);
      expect(result.supportsTools, ToolProbe.unsupported);
      expect(result.reply, 'Hello there!');
    });

    test('a server error on the tool request fails the test', () async {
      // Not "refuses tools": recording that would disable Organize over a
      // server that was only warming up.
      final provider = _FailsFirstChat('HTTP 500: model is loading');

      await expectLater(
        AiConnectionCheck.run(provider),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('loading'),
          ),
        ),
      );
    });

    test('a test forgets what was learned about the route first', () async {
      final provider = _CountsForget(['{"reply": "hi"}']);
      await AiConnectionCheck.run(provider);
      expect(provider.forgotten, 1);
    });

    test('only a 400 naming tools reads as refusing them', () {
      expect(
        AiConnectionCheck.refusesTools('HTTP 400: tools are not supported'),
        isTrue,
      );
      expect(
        AiConnectionCheck.refusesTools('HTTP 422: unknown field "functions"'),
        isTrue,
      );
      expect(AiConnectionCheck.refusesTools('HTTP 500: tool crashed'), isFalse);
      expect(AiConnectionCheck.refusesTools('HTTP 401: bad key'), isFalse);
    });

    test('a prose-only model gets a second ask, then is unsupported', () async {
      final provider = ScriptedProvider(['{"reply": "Hello there!"}']);

      final result = await AiConnectionCheck.run(provider);

      // The greeting, then one more tool-calling ask.
      expect(provider.calls, 2);
      expect(result.supportsTools, ToolProbe.unsupported);
      expect(result.reply, 'Hello there!');
      expect(result.truncated, isFalse);
      expect(result.limits.isEmpty, isTrue);
    });

    test('a model that ignores the format still counts as answering', () {
      expect(
        AiConnectionCheck.replyText('```json\n{"reply": "Hi"}\n```'),
        'Hi',
      );
      expect(AiConnectionCheck.replyText('  Hello!  '), 'Hello!');
      expect(AiConnectionCheck.replyText(''), '');
    });
  });

  // Through a real adapter, so the status code takes the path it takes in
  // the app: a fake provider throwing AiNetworkException hid that every
  // non-2xx reply came out as a plain AiException, read here as "refuses
  // tools" and recorded for good.
  group('probeTools through a real adapter', () {
    ({OpenAiProvider provider, List<http.BaseRequest> requests}) openAi(
      String host,
      int status,
      String body,
    ) {
      final requests = <http.BaseRequest>[];
      final provider = OpenAiProvider(
        AiConfig(
          provider: AiProviderType.openAi,
          endpoint: 'http://$host:1234',
          apiKey: '',
          model: 'probe-model',
        ),
        client: MockClient((request) async {
          requests.add(request);
          // retry-after: 0 keeps withRetry's backoff out of the test.
          return http.Response(
            body,
            status,
            headers: const {'retry-after': '0'},
          );
        }),
      );
      return (provider: provider, requests: requests);
    }

    for (final status in [401, 402, 429, 503]) {
      test('HTTP $status is inconclusive', () async {
        final (:provider, requests: _) = openAi(
          'probe-$status',
          status,
          jsonEncode({
            'error': {'message': 'not this time'},
          }),
        );

        final probe = await AiConnectionCheck.probeTools(provider);

        expect(probe.outcome, ToolProbe.inconclusive);
        expect(probe.error, startsWith('HTTP $status'));
      });
    }

    test('a 400 naming tools is unsupported', () async {
      final (:provider, :requests) = openAi(
        'probe-refuses',
        400,
        jsonEncode({
          'error': {'message': 'tools is not supported for this model'},
        }),
      );

      final probe = await AiConnectionCheck.probeTools(provider);

      expect(probe.outcome, ToolProbe.unsupported);
      expect(requests, hasLength(1));
    });

    test('a 404 is inconclusive and not asked twice', () async {
      final (:provider, :requests) = openAi(
        'probe-404',
        404,
        jsonEncode({
          'error': {'message': 'model not found'},
        }),
      );

      final probe = await AiConnectionCheck.probeTools(provider);

      expect(probe.outcome, ToolProbe.inconclusive);
      expect(probe.error, startsWith('HTTP 404: model not found'));
      expect(requests, hasLength(1));
    });

    for (final status in [408, 504]) {
      test(
        'a timed-out HTTP $status is inconclusive and not asked twice',
        () async {
          final (:provider, :requests) = openAi(
            'probe-timeout-$status',
            status,
            jsonEncode({
              'error': {'message': 'timed out'},
            }),
          );

          final probe = await AiConnectionCheck.probeTools(provider);

          expect(probe.outcome, ToolProbe.inconclusive);
          expect(probe.error, startsWith('HTTP $status'));
          // The first greeting may still be generating.
          expect(requests, hasLength(1));
        },
      );
    }

    // testWidgets for its fake clock: the probe's own cap is 90 s.
    testWidgets('its own timeout is asked again, for a model still loading', (
      tester,
    ) async {
      final provider = _NeverAnswers();
      ToolProbeResult? probe;
      unawaited(AiConnectionCheck.probeTools(provider).then((r) => probe = r));

      await tester.pump(AiConnectionCheck.timeout);
      await tester.pump(AiConnectionCheck.timeout);

      expect(provider.asked, 2);
      expect(probe?.outcome, ToolProbe.inconclusive);
      expect(probe?.error, contains('No reply within'));
    });

    test('one prose reply after a failed request is inconclusive', () async {
      // The model had one chance, not two; its single stray reply must not
      // be recorded as "does not call tools".
      var calls = 0;
      final provider = OpenAiProvider(
        const AiConfig(
          provider: AiProviderType.openAi,
          endpoint: 'http://probe-500-then-prose:1234',
          apiKey: '',
          model: 'probe-model',
        ),
        client: MockClient((_) async {
          // A 500 is not retried by withRetry, so this is the probe's own
          // first attempt.
          if (calls++ == 0) {
            return http.Response('{"error": {"message": "boom"}}', 500);
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Hello!'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
          );
        }),
      );

      final probe = await AiConnectionCheck.probeTools(provider);

      expect(calls, 2);
      expect(probe.outcome, ToolProbe.inconclusive);
      expect(probe.error, 'HTTP 500: boom');
    });

    test('every adapter reports an account or server status as such', () {
      // What keeps the probe honest is the exception type the adapter picks,
      // not only the probe's own reading of it.
      MockClient status(int code) => MockClient(
        (_) async => http.Response(
          '{"error": {"message": "no"}}',
          code,
          headers: const {'retry-after': '0'},
        ),
      );
      AiConfig config(AiProviderType type) => AiConfig(
        provider: type,
        endpoint: 'http://status-${type.name}.example',
        apiKey: 'k',
        model: 'm',
      );
      final adapters = <int, List<AiProvider>>{
        for (final code in [401, 503, 404])
          code: [
            OpenAiProvider(config(AiProviderType.openAi), client: status(code)),
            OpenAiResponsesProvider(
              config(AiProviderType.openAiResponses),
              client: status(code),
            ),
            AnthropicProvider(
              config(AiProviderType.anthropic),
              client: status(code),
            ),
            GoogleGenAiProvider(
              config(AiProviderType.googleGenAi),
              client: status(code),
            ),
          ],
      };
      for (final MapEntry(key: code, value: providers) in adapters.entries) {
        for (final provider in providers) {
          final matcher = isA<AiException>().having(
            (e) => e is AiNetworkException,
            'is AiNetworkException',
            code != 404,
          );
          expect(
            provider.chat(
              messages: const [UserMessage('hi')],
              tools: const [AiConnectionCheck.toolProbe],
            ),
            throwsA(matcher),
            reason: '${provider.runtimeType} $code',
          );
        }
      }
    });

    test("Anthropic's 529 is inconclusive", () async {
      final provider = AnthropicProvider(
        const AiConfig(
          provider: AiProviderType.anthropic,
          endpoint: 'http://probe-529.example',
          apiKey: 'sk-ant',
          model: 'claude-sonnet-5',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'type': 'error',
              'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
            }),
            529,
            headers: const {'retry-after': '0'},
          ),
        ),
      );

      final probe = await AiConnectionCheck.probeTools(provider);

      expect(probe.outcome, ToolProbe.inconclusive);
      expect(probe.error, 'HTTP 529: Overloaded');
    });
  });
}

/// Refuses any request that carries tools; answers a plain completion.
class _RefusesTools extends ScriptedProvider {
  final void Function() onChat;
  _RefusesTools(this.onChat) : super(['{"reply": "Hello there!"}']);

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) async {
    onChat();
    throw const AiException('HTTP 400: tools are not supported');
  }
}

class _FailsFirstChat extends ScriptedProvider {
  final String error;
  _FailsFirstChat(this.error) : super(['{"reply": "hi"}']);

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) async => throw AiException(error);
}

class _CountsForget extends ScriptedProvider {
  int forgotten = 0;
  _CountsForget(super.replies);

  @override
  void forgetLearned() => forgotten++;
}

/// Never answers: only the probe's own timeout ends a request.
class _NeverAnswers extends ScriptedProvider {
  var asked = 0;
  _NeverAnswers() : super(['{"reply": "hi"}']);

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) {
    asked++;
    return Completer<ChatResult>().future;
  }
}
