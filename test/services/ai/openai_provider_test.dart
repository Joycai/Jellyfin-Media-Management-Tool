import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
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

/// A Chinese error message needs its charset, or `http.Response` refuses it.
const _utf8Json = {'content-type': 'application/json; charset=utf-8'};

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

  group('failures that arrive with HTTP 200', () {
    http.Response stream(List<Map<String, Object?>> events) => http.Response(
      [...events.map(_event), 'data: [DONE]\n\n'].join(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );

    Map<String, Object?> chunk(String? content, {String? finish}) => {
      'choices': [
        {
          'delta': {'content': ?content},
          'finish_reason': finish,
        },
      ],
    };

    test('a content_filter finish throws instead of ending quietly', () async {
      final provider = OpenAiProvider(
        _config('filtered'),
        client: MockClient(
          (_) async => stream([
            chunk('partial '),
            chunk(null, finish: 'content_filter'),
          ]),
        ),
      );

      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>()
              .having((e) => e, 'type', isNot(isA<AiNetworkException>()))
              .having((e) => e.message, 'message', contains('content filter')),
        ),
      );
    });

    test("Zhipu's sensitive finish is a filter too", () async {
      final provider = OpenAiProvider(
        _config('sensitive'),
        client: MockClient(
          (_) async => stream([chunk('x', finish: 'sensitive')]),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('"sensitive"'),
          ),
        ),
      );
    });

    test('an upstream network_error is a transport failure', () async {
      final provider = OpenAiProvider(
        _config('upstream-broke'),
        client: MockClient(
          (_) async => stream([chunk('half', finish: 'network_error')]),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('context-window exhaustion is not advice to raise the cap', () async {
      final provider = OpenAiProvider(
        _config('context-full'),
        client: MockClient(
          (_) async =>
              stream([chunk('x', finish: 'model_context_window_exceeded')]),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('context window'),
          ),
        ),
      );
    });

    test("OpenRouter's error finish is an upstream failure", () async {
      final provider = OpenAiProvider(
        _config('openrouter-error'),
        client: MockClient((_) async => stream([chunk('x', finish: 'error')])),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('MiniMax base_resp is reported as the account error it is', () async {
      final provider = OpenAiProvider(
        _config('minimax'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': null,
              'base_resp': {
                'status_code': 1008,
                'status_msg': 'insufficient balance',
              },
            }),
            200,
          ),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          // An account problem settles nothing about the model.
          isA<AiNetworkException>().having(
            (e) => e.message,
            'message',
            'Model error 1008: insufficient balance',
          ),
        ),
      );
    });

    test('a non-streamed error object is not an empty reply', () async {
      final provider = OpenAiProvider(
        _config('error-envelope'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'key expired'},
            }),
            200,
          ),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            'Model error: key expired',
          ),
        ),
      );
    });

    test('an unexpected completion shape is named, not a TypeError', () async {
      final provider = OpenAiProvider(
        _config('odd-shape'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'hi'},
                  'finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': 'twelve'},
            }),
            200,
          ),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('shape'),
          ),
        ),
      );
    });
  });

  group('content as a list of parts', () {
    const parts = [
      {'type': 'text', 'text': 'Hello, '},
      {'type': 'image_url', 'image_url': 'ignored'},
      {'type': 'text', 'text': 'world'},
    ];

    test('is read when streamed', () async {
      final provider = OpenAiProvider(
        _config('parts-stream'),
        client: MockClient(
          (_) async => http.Response(
            [
              _event({
                'choices': [
                  {
                    'delta': {'content': parts},
                    'finish_reason': 'stop',
                  },
                ],
              }),
              'data: [DONE]\n\n',
            ].join(),
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      final result = await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [],
      );
      expect(result.text, 'Hello, world');
    });

    test('is read from a plain completion', () async {
      final provider = OpenAiProvider(
        _config('parts-plain'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': parts},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
          ),
        ),
      );
      final result = await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [],
      );
      expect(result.text, 'Hello, world');
    });
  });

  group('platform thinking switches', () {
    Future<Map<String, dynamic>> sent(
      String endpoint,
      String model, {
      bool thinking = false,
    }) async {
      late Map<String, dynamic> body;
      await OpenAiProvider(
        AiConfig(
          provider: AiProviderType.openAi,
          endpoint: endpoint,
          apiKey: 'k',
          model: model,
          thinkingEnabled: thinking,
        ),
        client: MockClient((request) async {
          body = _body(request);
          return _reply('ok');
        }),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      return body;
    }

    test('Zhipu gets thinking.type and no ladder', () async {
      final body = await sent(
        'https://open.bigmodel.cn/api/paas/v4',
        'glm-4.6',
      );
      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('chat_template_kwargs'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('DashScope gets enable_thinking both ways', () async {
      final off = await sent(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'qwen3-max',
      );
      expect(off['enable_thinking'], isFalse);
      expect(off.containsKey('chat_template_kwargs'), isFalse);

      final on = await sent(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'qwen-plus',
        thinking: true,
      );
      expect(on['enable_thinking'], isTrue);
    });

    test('DeepSeek gets thinking.type even for an unknown family', () async {
      final body = await sent('https://api.deepseek.com', 'deepseek-chat');
      expect(body['thinking'], {'type': 'disabled'});
    });

    test('a 400 that only mentions thinking keeps the switch', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = _body(request);
        bodies.add(body);
        return bodies.length == 1
            ? http.Response(
                jsonEncode({
                  'error': {
                    'message':
                        'Missing reasoning_content in thinking mode, see '
                        'https://api-docs.deepseek.com/guides/thinking_mode; '
                        'temperature is not supported',
                  },
                }),
                400,
              )
            : _reply('ok');
      });
      AiConfig config() => const AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'https://api.deepseek.com',
        apiKey: 'k-thinking-prose',
        model: 'deepseek-chat',
      );
      await OpenAiProvider(
        config(),
        client: client,
      ).chat(messages: const [UserMessage('u')], tools: const []);
      await OpenAiProvider(
        config(),
        client: client,
      ).chat(messages: const [UserMessage('u')], tools: const []);

      expect(bodies.last['thinking'], {'type': 'disabled'});
      expect(bodies.last.containsKey('temperature'), isFalse);
    });

    test('a model that must reason drops the platform switch', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = _body(request);
        bodies.add(body);
        return body.containsKey('reasoning')
            ? http.Response(
                jsonEncode({
                  'error': {
                    'message':
                        'Reasoning is mandatory for this endpoint and cannot '
                        'be disabled.',
                  },
                }),
                400,
              )
            : _reply('ok');
      });
      await OpenAiProvider(
        const AiConfig(
          provider: AiProviderType.openAi,
          endpoint: 'https://openrouter.ai/api/v1',
          apiKey: 'k-mandatory',
          model: 'openai/o4-mini',
        ),
        client: client,
      ).chat(messages: const [UserMessage('u')], tools: const []);

      expect(bodies.first['reasoning'], {'enabled': false});
      expect(bodies.last.containsKey('reasoning'), isFalse);
    });

    test('a model that always reasons is not asked off again', () async {
      // Zhipu's 5.3 generation: the refusal does not name `thinking`
      // (KB 03 §3.1, measured 2026-09-19).
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = _body(request);
        bodies.add(body);
        // A retry that never drops the switch would otherwise spin forever:
        // a mock reply never yields to the timer that times the test out.
        if (bodies.length > 8) throw StateError('the retries never stopped');
        return (body['thinking'] as Map?)?['type'] == 'disabled'
            ? http.Response(
                jsonEncode({
                  'error': {'code': '1210', 'message': '该模型始终思考，不支持关闭思考'},
                }),
                400,
                headers: _utf8Json,
              )
            : _reply('ok');
      });
      AiConfig config({bool thinking = false}) => AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: 'k-always-reasons',
        model: 'glm-5.3',
        platform: 'zhipu',
        thinkingEnabled: thinking,
      );

      final reply = await OpenAiProvider(
        config(),
        client: client,
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(reply.text, 'ok');
      expect(bodies, hasLength(2));
      expect(bodies.first['thinking'], {'type': 'disabled'});
      expect(bodies.last.containsKey('thinking'), isFalse);
      final learned = OpenAiProvider(config(), client: client).learned;
      expect(learned.thinkingOffTried, {LearnedBehaviour.dialectOff});
      expect(learned.rejectedFields, isEmpty);

      // Remembered: the next request goes out without the switch.
      await OpenAiProvider(
        config(),
        client: client,
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(bodies, hasLength(3));
      expect(bodies.last.containsKey('thinking'), isFalse);
      // The settings preview shows the request a task now sends.
      final preview = await OpenAiProvider(
        config(),
        client: client,
      ).previewRequest(messages: const [UserMessage('u')], tools: const []);
      expect(preview.body.containsKey('thinking'), isFalse);

      // Asking it on is a different request, and is still sent.
      await OpenAiProvider(
        config(thinking: true),
        client: client,
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(bodies.last['thinking'], {'type': 'enabled'});
      final onPreview = await OpenAiProvider(
        config(thinking: true),
        client: client,
      ).previewRequest(messages: const [UserMessage('u')], tools: const []);
      expect(onPreview.body['thinking'], {'type': 'enabled'});
    });

    test('a refusal while asking reasoning on teaches nothing', () async {
      // Only a refused *off* is learned; learning it here would retry the
      // same request, since *on* is still sent.
      var sent = 0;
      final provider = OpenAiProvider(
        const AiConfig(
          provider: AiProviderType.openAi,
          endpoint: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: 'k-refused-on',
          model: 'glm-5.3',
          platform: 'zhipu',
          thinkingEnabled: true,
        ),
        client: MockClient((request) async {
          if (++sent > 8) throw StateError('the retries never stopped');
          return http.Response(
            jsonEncode({
              'error': {'code': '1210', 'message': '该模型始终思考，不支持关闭思考'},
            }),
            400,
            headers: _utf8Json,
          );
        }),
      );

      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiException>()),
      );
      expect(sent, 1);
      expect(provider.learned.isEmpty, isTrue);
    });

    test('an unrelated 400 on a switch route teaches nothing', () async {
      // The second names no field and says `mandatory`, which a refusal of
      // the switch only counts as beside the field's name.
      for (final (i, message) in const [
        'messages 参数非法',
        "'messages' is mandatory",
      ].indexed) {
        var sent = 0;
        final provider = OpenAiProvider(
          AiConfig(
            provider: AiProviderType.openAi,
            endpoint: 'https://open.bigmodel.cn/api/paas/v4',
            apiKey: 'k-unrelated-400-$i',
            model: 'glm-5.3',
            platform: 'zhipu',
          ),
          client: MockClient((request) async {
            sent++;
            return http.Response(
              jsonEncode({
                'error': {'code': '1214', 'message': message},
              }),
              400,
              headers: _utf8Json,
            );
          }),
        );

        await expectLater(
          provider.chat(messages: const [UserMessage('u')], tools: const []),
          throwsA(isA<AiException>()),
          reason: message,
        );
        expect(sent, 1, reason: message);
        expect(provider.learned.isEmpty, isTrue, reason: message);
      }
    });

    test('any other server sends no platform field', () async {
      final body = await sent('https://api.openai.com/v1', 'gpt-5.4-mini');
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('enable_thinking'), isFalse);
    });
  });

  test(
    'every request sent, refused ones included, goes to the API log',
    () async {
      final dir = await Directory.systemTemp.createTemp('openai_log');
      addTearDown(() async {
        ApiLog.instance
          ..enabled = false
          ..directory = null;
        await dir.delete(recursive: true);
      });
      ApiLog.instance
        ..directory = dir
        ..enabled = true;

      final provider = OpenAiProvider(
        _config('logged', apiKey: 'sk-never-logged'),
        client: MockClient((request) async {
          final body = _body(request);
          return body.containsKey('stream_options')
              ? http.Response(
                  jsonEncode({
                    'error': {'message': 'Unknown field: stream_options'},
                  }),
                  400,
                )
              : _reply('{"ok": true}');
        }),
      );
      await provider.chat(messages: const [UserMessage('u')], tools: const []);
      await ApiLog.instance.flush();

      final text = await ApiLog.instance.currentFile!.readAsString();
      final entries = [
        for (final line in text.trim().split('\n'))
          jsonDecode(line) as Map<String, dynamic>,
      ];
      expect(entries.map((e) => e['status']), [400, 200]);
      expect(entries.first['error'], contains('stream_options'));
      expect((entries.last['response'] as Map)['finish_reason'], 'stop');
      expect(text, isNot(contains('sk-never-logged')));
    },
  );

  test('what a route refused is remembered across providers', () async {
    var sent = 0;
    MockClient client() => MockClient((request) async {
      sent++;
      return _body(request).containsKey('stream_options')
          ? http.Response(
              jsonEncode({
                'error': {'message': 'Unknown field: stream_options'},
              }),
              400,
            )
          : _reply('ok');
    });
    await OpenAiProvider(
      _config('remembered'),
      client: client(),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(sent, 2);

    final second = OpenAiProvider(_config('remembered'), client: client());
    await second.chat(messages: const [UserMessage('u')], tools: const []);
    expect(sent, 3);

    // A connection test forgets it, so the next request finds out again.
    second.forgetLearned();
    expect(
      LearnedStore.instance.entries.keys.where((k) => k.contains('remembered')),
      isEmpty,
    );
  });

  test('an image goes as an image_url content part', () async {
    late Map<String, dynamic> body;
    await OpenAiProvider(
      _config('image-part'),
      client: MockClient((request) async {
        body = _body(request);
        return _reply('ok');
      }),
    ).chat(
      messages: [
        UserMessage(
          'look',
          images: [
            ImagePart(bytes: Uint8List.fromList([1, 2, 3])),
          ],
        ),
      ],
      tools: const [],
    );
    final content = (body['messages'] as List).single['content'] as List;
    expect(content.first, {'type': 'text', 'text': 'look'});
    expect(content.last, {
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,AQID'},
    });
  });
}

String _event(Map<String, Object?> event) => 'data: ${jsonEncode(event)}\n\n';
