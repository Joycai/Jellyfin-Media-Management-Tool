import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/connection_check.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_provider.dart';

// Every test uses its own host: the provider remembers server kinds, refused
// fields and how far it got turning reasoning off, for the whole process.
AiConfig _config(String host, String model, {bool thinking = false}) =>
    AiConfig(
      provider: AiProviderType.openAi,
      endpoint: 'http://$host:1234/v1',
      apiKey: '',
      model: model,
      thinkingEnabled: thinking,
    );

String _event(Map<String, Object?> event) => 'data: ${jsonEncode(event)}\n\n';

http.Response _stream({String content = '{}', String? reasoning}) =>
    http.Response(
      [
        if (reasoning != null)
          _event({
            'choices': [
              {
                'delta': {'reasoning_content': reasoning},
              },
            ],
          }),
        _event({
          'choices': [
            {
              'delta': {'content': content},
              'finish_reason': 'stop',
            },
          ],
        }),
        'data: [DONE]\n\n',
      ].join(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

http.Response _refuse(String message) => http.Response(
  jsonEncode({
    'error': {'message': message},
  }),
  400,
);

/// A fake server: [kind] decides which discovery route answers, [chat] serves
/// completions. Every completion body is recorded.
class _Server {
  final ServerKind kind;
  final http.Response Function(Map<String, dynamic> body) chat;
  final List<Map<String, dynamic>> bodies = [];

  _Server(this.kind, this.chat);

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/v1/chat/completions') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      return chat(body);
    }
    return switch ((kind, path)) {
      (ServerKind.lmStudio, '/api/v0/models') => http.Response(
        jsonEncode({'data': <Object>[]}),
        200,
      ),
      (ServerKind.ollama, '/api/version') => http.Response(
        jsonEncode({'version': '0.12.0'}),
        200,
      ),
      (ServerKind.llamaCpp, '/props') => http.Response(
        jsonEncode({
          'default_generation_settings': {'n_ctx': 4096},
        }),
        200,
      ),
      (ServerKind.vllm, '/version') => http.Response(
        jsonEncode({'version': '0.9.0'}),
        200,
      ),
      _ => http.Response('Not found', 404),
    };
  });

  String system(int call) =>
      ((bodies[call]['messages'] as List).first as Map)['content'] as String;
}

Future<AiResponse> _ask(AiConfig config, _Server server) => OpenAiProvider(
  config,
  client: server.client,
).complete(systemPrompt: 'system', userPrompt: 'user');

void main() {
  group('sampling', () {
    test('a preset is sent in full, neutral values included', () async {
      final server = _Server(ServerKind.llamaCpp, (_) => _stream());

      await _ask(_config('preset', 'qwen3.8-27b-uncensored'), server);

      final body = server.bodies.single;
      expect(body['temperature'], 0.7);
      expect(body['top_p'], 0.8);
      expect(body['top_k'], 20);
      expect(body['min_p'], 0);
      expect(body['presence_penalty'], 1.5);
      expect(body['repeat_penalty'], 1.0);
    });

    test(
      'a model outside every preset sends only the old temperature',
      () async {
        final server = _Server(ServerKind.unknown, (_) => _stream());

        await _ask(_config('nopreset', 'spark-x2.5-4b'), server);

        final body = server.bodies.single;
        expect(body['temperature'], 0.2);
        for (final key in [
          'top_p',
          'top_k',
          'min_p',
          'presence_penalty',
          'repeat_penalty',
          'chat_template_kwargs',
          'reasoning_effort',
        ]) {
          expect(body.containsKey(key), isFalse, reason: key);
        }
      },
    );

    test('a field refused by name is dropped and stays dropped', () async {
      final server = _Server(
        ServerKind.unknown,
        (body) => body.containsKey('top_k')
            ? _refuse('Unrecognized request argument supplied: top_k')
            : _stream(),
      );
      final config = _config('refuses', 'qwen2.5-7b-instruct');

      await _ask(config, server);
      await _ask(config, server);

      expect(server.bodies.map((b) => b.containsKey('top_k')), [
        true,
        false,
        false,
      ]);
      expect(server.bodies.last['repeat_penalty'], 1.05);
    });

    test('a user override replaces the preset value', () async {
      final server = _Server(ServerKind.llamaCpp, (_) => _stream());
      const config = AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'http://override:1234/v1',
        apiKey: '',
        model: 'qwen3.8-27b',
        temperature: 0.4,
      );

      await _ask(config, server);

      expect(server.bodies.single['temperature'], 0.4);
      expect(server.bodies.single['top_p'], 0.8);
    });
  });

  group('thinking off', () {
    test(
      'LM Studio: the template switch first, then reasoning_effort',
      () async {
        final server = _Server(
          ServerKind.lmStudio,
          (_) => _stream(content: '{"reply": "hi"}', reasoning: 'A greeting.'),
        );
        final config = _config('lmstudio-off', 'qwen3.8-27b-uncensored');

        final first = await _ask(config, server);
        expect(server.bodies[0]['chat_template_kwargs'], {
          'enable_thinking': false,
        });
        expect(first.reasoned, isTrue);
        expect(first.thinkingOffPending, isTrue);

        final second = await _ask(config, server);
        expect(server.bodies[1].containsKey('chat_template_kwargs'), isFalse);
        expect(server.bodies[1]['reasoning_effort'], 'none');
        expect(second.thinkingOffPending, isFalse, reason: 'no way left');
      },
    );

    test('a way that works is kept', () async {
      final server = _Server(ServerKind.llamaCpp, (_) => _stream());
      final config = _config('kept', 'qwen3.8-27b');

      await _ask(config, server);
      await _ask(config, server);

      expect(server.bodies.map((b) => b.containsKey('chat_template_kwargs')), [
        true,
        true,
      ]);
    });

    test('Ollama is asked through reasoning_effort only', () async {
      final server = _Server(ServerKind.ollama, (_) => _stream());

      await _ask(_config('ollama-off', 'qwen3.8-27b'), server);

      expect(server.bodies.single['reasoning_effort'], 'none');
      expect(server.bodies.single.containsKey('chat_template_kwargs'), isFalse);
    });

    test(
      'a refused template switch moves straight on to the next way',
      () async {
        final server = _Server(
          ServerKind.llamaCpp,
          (body) => body.containsKey('chat_template_kwargs')
              ? _refuse('unknown field: chat_template_kwargs')
              : _stream(),
        );

        await _ask(_config('rejects-template', 'glm-4.6'), server);

        expect(server.bodies, hasLength(2));
        expect(server.bodies.last['reasoning_effort'], 'none');
      },
    );

    test('Qwen3 ends with the /no_think soft switch in the prompt', () async {
      final server = _Server(ServerKind.lmStudio, (body) {
        final system =
            ((body['messages'] as List).first as Map)['content'] as String;
        return system.endsWith('/no_think')
            ? _stream(content: '<think>\n\n</think>\n{"reply": "hi"}')
            : _stream(content: '{"reply": "hi"}', reasoning: 'Thinking.');
      });
      final config = _config('soft-switch', 'qwen3-8b');

      AiResponse response;
      do {
        response = await _ask(config, server);
      } while (response.thinkingOffPending);

      expect(server.bodies, hasLength(3));
      expect(response.reasoned, isFalse);
      expect(response.text, '{"reply": "hi"}');
    });

    test(
      'with thinking on nothing asks it off, and its values apply',
      () async {
        final server = _Server(ServerKind.lmStudio, (_) => _stream());

        await _ask(
          _config('thinking-on', 'qwen3.8-27b', thinking: true),
          server,
        );

        final body = server.bodies.single;
        expect(body['temperature'], 1.0);
        expect(body['presence_penalty'], 0);
        expect(body.containsKey('chat_template_kwargs'), isFalse);
        expect(body.containsKey('reasoning_effort'), isFalse);
      },
    );

    test(
      'gpt-oss cannot stop reasoning, so it is asked for the least',
      () async {
        final server = _Server(ServerKind.ollama, (_) => _stream());

        await _ask(_config('gpt-oss', 'gpt-oss-20b'), server);

        expect(server.bodies.single['reasoning_effort'], 'low');
      },
    );

    test('Gemma 4 reasons only when asked, through its prompt token', () async {
      final server = _Server(ServerKind.lmStudio, (_) => _stream());

      await _ask(_config('gemma-off', 'gemma4-26b'), server);
      await _ask(_config('gemma-on', 'gemma4-26b', thinking: true), server);

      expect(server.system(0), 'system');
      expect(server.system(1), startsWith('<|think|>'));
    });
  });

  test('the connection check walks the ways until reasoning stops', () async {
    final server = _Server(
      ServerKind.lmStudio,
      (body) => body.containsKey('chat_template_kwargs')
          ? _stream(content: '{"reply": "hi"}', reasoning: 'Let me think.')
          : _stream(content: '{"reply": "hi"}'),
    );

    final result = await AiConnectionCheck.run(
      OpenAiProvider(
        _config('check-off', 'qwen3.6-27b'),
        client: server.client,
      ),
    );

    // The greetings only; the tool check that follows carries `tools`.
    expect(server.bodies.where((b) => !b.containsKey('tools')), hasLength(2));
    expect(result.reasoned, isFalse);
    expect(result.serverKind, ServerKind.lmStudio);
    expect(result.reply, 'hi');
  });

  group('splitReasoning', () {
    test('a leading think block is separated from the answer', () {
      expect(
        OpenAiProvider.splitReasoning('<think>\nplan {x}\n</think>\n{"a": 1}'),
        ('{"a": 1}', true),
      );
    });

    test('an empty block is not reasoning', () {
      expect(OpenAiProvider.splitReasoning('<think>\n\n</think>\n{"a": 1}'), (
        '{"a": 1}',
        false,
      ));
    });

    test('a lone closing tag still ends a leading block', () {
      expect(OpenAiProvider.splitReasoning('plan\n</think>\n{"a": 1}'), (
        '{"a": 1}',
        true,
      ));
    });

    test('a tag inside the answer is left alone', () {
      expect(OpenAiProvider.splitReasoning('{"a": "<think>"}'), (
        '{"a": "<think>"}',
        false,
      ));
    });
  });
}
