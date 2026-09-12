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

  test('streams the reply, keeping content and dropping reasoning', () async {
    late Map<String, dynamic> sent;
    final provider = OpenAiProvider(
      _config('streamed'),
      client: MockClient((request) async {
        sent = _body(request);
        return http.Response(
          [
            _event({
              'choices': [
                {
                  'delta': {
                    'role': 'assistant',
                    'reasoning_content': 'A greeting {with braces}.',
                  },
                  'finish_reason': null,
                },
              ],
            }),
            _event({
              'choices': [
                {
                  'delta': {'content': '{"reply": '},
                  'finish_reason': null,
                },
              ],
            }),
            _event({
              'choices': [
                {
                  'delta': {'content': '"Hi"}'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            _event({
              'choices': <Object>[],
              'usage': {'prompt_tokens': 91, 'completion_tokens': 74},
            }),
            'data: [DONE]\n\n',
          ].join(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final response = await provider.complete(
      systemPrompt: 's',
      userPrompt: 'u',
    );

    expect(sent['stream'], isTrue);
    expect(sent['stream_options'], {'include_usage': true});
    expect(response.text, '{"reply": "Hi"}');
    expect(response.finishReason, 'stop');
    expect(response.promptTokens, 91);
    expect(response.completionTokens, 74);
  });

  test('assembles cumulative tool-call id and name fragments once', () async {
    final provider = OpenAiProvider(
      _config('cumulative-tool-fragments'),
      client: MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              [
                _event({
                  'choices': [
                    {
                      'delta': {
                        'tool_calls': [
                          {
                            'index': 0,
                            'id': 'call',
                            'function': {'name': 'sub'},
                          },
                        ],
                      },
                    },
                  ],
                }),
                _event({
                  'choices': [
                    {
                      'delta': {
                        'tool_calls': [
                          {
                            'index': 0,
                            'id': 'call_1',
                            'function': {
                              'name': 'submit_fields',
                              'arguments': '{"title":"X"}',
                            },
                          },
                        ],
                      },
                      'finish_reason': 'tool_calls',
                    },
                  ],
                }),
                'data: [DONE]\n\n',
              ].join(),
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final response = await provider.chat(
      messages: const [UserMessage('read the page')],
      tools: const [
        ToolDefinition(
          name: 'submit_fields',
          description: 'submit',
          parameters: {'type': 'object'},
        ),
      ],
    );

    expect(response.toolCalls, hasLength(1));
    expect(response.toolCalls.single.id, 'call_1');
    expect(response.toolCalls.single.name, 'submit_fields');
    expect(response.toolCalls.single.arguments, '{"title":"X"}');
  });

  test('retries without stream_options when a server refuses them', () async {
    final bodies = <Map<String, dynamic>>[];
    final provider = OpenAiProvider(
      _config('nostreamoptions'),
      client: MockClient((request) async {
        final body = _body(request);
        bodies.add(body);
        return body.containsKey('stream_options')
            ? http.Response(
                jsonEncode({
                  'error': {
                    'message':
                        'Unrecognized request argument supplied: stream_options',
                  },
                }),
                400,
              )
            : _reply('{}');
      }),
    );

    await provider.complete(systemPrompt: 's', userPrompt: 'u');

    expect(bodies, hasLength(2));
    expect(bodies.last['stream'], isTrue);
  });

  test('a stream that goes silent fails once, without a retry', () async {
    var sends = 0;
    final provider = OpenAiProvider(
      _config('silent'),
      idleTimeout: const Duration(milliseconds: 50),
      client: MockClient.streaming((request, _) async {
        sends++;
        return http.StreamedResponse(
          // One event, then nothing, and the connection never closes.
          Stream<List<int>>.multi(
            (controller) => controller.add(
              utf8.encode(
                _event({
                  'choices': [
                    {
                      'delta': {'content': '{"actions": ['},
                    },
                  ],
                }),
              ),
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    await expectLater(
      provider.complete(systemPrompt: 's', userPrompt: 'u'),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('stopped sending'),
        ),
      ),
    );
    expect(sends, 1);
  });

  test('a server that never starts answering times out once', () async {
    var sends = 0;
    final provider = OpenAiProvider(
      _config('mute'),
      firstEventTimeout: const Duration(milliseconds: 50),
      client: MockClient.streaming((request, _) async {
        sends++;
        return http.StreamedResponse(
          Stream<List<int>>.multi((_) {}),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    await expectLater(
      provider.complete(systemPrompt: 's', userPrompt: 'u'),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('No response'),
        ),
      ),
    );
    expect(sends, 1);
  });

  group('endpoint normalization', () {
    Future<Uri> requestedFor(String endpoint) async {
      late http.BaseRequest seen;
      await OpenAiProvider(
        AiConfig(
          provider: AiProviderType.openAi,
          endpoint: endpoint,
          apiKey: '',
          model: 'local-model',
        ),
        client: MockClient((request) async {
          seen = request;
          return _reply('{}');
        }),
      ).complete(systemPrompt: 's', userPrompt: 'u');
      return seen.url;
    }

    test('a bare origin gets /v1, trailing slashes and all', () async {
      expect(
        (await requestedFor('http://bare-origin:1234')).toString(),
        'http://bare-origin:1234/v1/chat/completions',
      );
      expect(
        (await requestedFor('http://trailing:1234///')).toString(),
        'http://trailing:1234/v1/chat/completions',
      );
    });

    test('a URL that already has a path is left exactly as typed', () async {
      // A relay routes below its own prefix and Azure below a deployment
      // name. Appending a version segment there is a 404 whose cause is
      // invisible, on the one kind of endpoint users type most carefully.
      expect(
        (await requestedFor('https://relay.example.com/api/openai')).toString(),
        'https://relay.example.com/api/openai/chat/completions',
      );
      expect(
        (await requestedFor('https://host/v1')).toString(),
        'https://host/v1/chat/completions',
      );
    });
  });

  test('what one key was refused is not applied to another', () async {
    AiConfig keyed(String key) => AiConfig(
      provider: AiProviderType.openAi,
      endpoint: 'http://shared-endpoint:1234',
      apiKey: key,
      model: 'local-model',
      maxOutputTokens: 256,
      topK: 40,
    );

    final bodies = <Map<String, dynamic>>[];
    http.Client refusesTopKFor(String key) => MockClient((request) async {
      bodies.add(_body(request));
      if (request.headers['Authorization'] == 'Bearer $key' &&
          bodies.last.containsKey('top_k')) {
        return http.Response(
          jsonEncode({
            'error': {'message': "Unsupported parameter: 'top_k'"},
          }),
          400,
        );
      }
      return _reply('{}');
    });

    await OpenAiProvider(
      keyed('sk-first'),
      client: refusesTopKFor('sk-first'),
    ).complete(systemPrompt: 's', userPrompt: 'u');
    expect(bodies, hasLength(2), reason: 'refused once, then dropped');
    expect(bodies.last.containsKey('top_k'), isFalse);

    bodies.clear();
    await OpenAiProvider(
      keyed('sk-second'),
      client: refusesTopKFor('sk-first'),
    ).complete(systemPrompt: 's', userPrompt: 'u');

    // The second account shares the URL and the model but not the refusal:
    // a gateway that routes by token can serve the two quite differently.
    expect(bodies, hasLength(1));
    expect(bodies.single['top_k'], 40);
  });
}

String _event(Map<String, Object?> event) => 'data: ${jsonEncode(event)}\n\n';
