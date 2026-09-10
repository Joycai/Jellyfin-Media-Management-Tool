import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_provider.dart';

// Every test uses its own host: the provider remembers the JSON mode a server
// accepted for the rest of the process.
AiConfig _config(String host, {String apiKey = '', int? maxOutput}) => AiConfig(
  provider: AiProviderType.openAi,
  endpoint: 'http://$host:1234',
  apiKey: apiKey,
  model: 'local-model',
  maxOutputTokens: maxOutput,
);

http.Response _reply(String content, {String finishReason = 'stop'}) =>
    http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
            'finish_reason': finishReason,
          },
        ],
        'usage': {'prompt_tokens': 12, 'completion_tokens': 3},
      }),
      200,
    );

Map<String, dynamic> _body(http.BaseRequest request) =>
    jsonDecode((request as http.Request).body) as Map<String, dynamic>;

void main() {
  test('a keyless profile sends no Authorization header', () async {
    late http.BaseRequest seen;
    final provider = OpenAiProvider(
      _config('keyless'),
      client: MockClient((request) async {
        seen = request;
        return _reply('{}');
      }),
    );

    await provider.complete(systemPrompt: 's', userPrompt: 'u');

    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(seen.url.toString(), 'http://keyless:1234/v1/chat/completions');
  });

  test('a key is sent as a bearer token', () async {
    late http.BaseRequest seen;
    await OpenAiProvider(
      _config('keyed', apiKey: ' sk-test '),
      client: MockClient((request) async {
        seen = request;
        return _reply('{}');
      }),
    ).complete(systemPrompt: 's', userPrompt: 'u');

    expect(seen.headers['Authorization'], 'Bearer sk-test');
  });

  test('steps down to json_schema when json_object is refused', () async {
    final formats = <Object?>[];
    final client = MockClient((request) async {
      final type = (_body(request)['response_format'] as Map?)?['type'];
      formats.add(type);
      if (type == 'json_object') {
        // LM Studio's wording, including its bare-string error shape.
        return http.Response(
          jsonEncode({
            'error': "'response_format.type' must be 'json_schema' or 'text'",
          }),
          400,
        );
      }
      return _reply('{"ok": true}');
    });

    final response = await OpenAiProvider(
      _config('lmstudio'),
      client: client,
    ).complete(systemPrompt: 's', userPrompt: 'u');
    expect(response.text, '{"ok": true}');
    expect(formats, ['json_object', 'json_schema']);

    // The accepted mode is remembered, so the next request goes straight to it.
    await OpenAiProvider(
      _config('lmstudio'),
      client: client,
    ).complete(systemPrompt: 's', userPrompt: 'u');
    expect(formats, ['json_object', 'json_schema', 'json_schema']);
  });

  test('drops response_format when no JSON mode is accepted', () async {
    final bodies = <Map<String, dynamic>>[];
    final provider = OpenAiProvider(
      _config('plain'),
      client: MockClient((request) async {
        final body = _body(request);
        bodies.add(body);
        return body.containsKey('response_format')
            ? http.Response(
                jsonEncode({
                  'error': {'message': 'response_format is not supported'},
                }),
                400,
              )
            : _reply('{}');
      }),
    );

    await provider.complete(systemPrompt: 's', userPrompt: 'u');

    expect(bodies, hasLength(3));
    expect(bodies.last.containsKey('response_format'), isFalse);
  });

  test('an unrelated 400 fails with the server\'s own words', () async {
    final provider = OpenAiProvider(
      _config('unloaded'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'No models loaded. Please load a model first.'}),
          400,
        ),
      ),
    );

    await expectLater(
      provider.complete(systemPrompt: 's', userPrompt: 'u'),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          'HTTP 400: No models loaded. Please load a model first.',
        ),
      ),
    );
  });

  test('sends the output cap, renamed when the model insists', () async {
    final keys = <String>[];
    final provider = OpenAiProvider(
      _config('reasoning', maxOutput: 2048),
      client: MockClient((request) async {
        final body = _body(request);
        keys.addAll(body.keys.where((k) => k.startsWith('max_')));
        if (body.containsKey('max_tokens')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    "Unsupported parameter: 'max_tokens' is not supported "
                    "with this model. Use 'max_completion_tokens' instead.",
              },
            }),
            400,
          );
        }
        return _reply('{}');
      }),
    );

    await provider.complete(systemPrompt: 's', userPrompt: 'u');

    expect(keys, ['max_tokens', 'max_completion_tokens']);
  });

  test('flags a reply cut off at the output limit', () async {
    final response = await OpenAiProvider(
      _config('cutoff'),
      client: MockClient(
        (_) async => _reply('{"actions": [', finishReason: 'length'),
      ),
    ).complete(systemPrompt: 's', userPrompt: 'u');

    expect(response.truncated, isTrue);
  });

  test('detectLimits reads the context LM Studio loaded', () async {
    final provider = OpenAiProvider(
      _config('detect'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v0/models') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'local-model',
                  'loaded_context_length': 8192,
                  'max_context_length': 32768,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      }),
    );

    final limits = await provider.detectLimits();

    expect(limits.contextWindow, 8192);
    expect(limits.source, 'LM Studio');
    expect(limits.isModelMaximum, isFalse);
  });
}
