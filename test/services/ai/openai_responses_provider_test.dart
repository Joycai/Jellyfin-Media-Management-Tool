import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_responses_provider.dart';

AiConfig _config(
  String host, {
  String model = 'gpt-5.4',
  bool thinking = false,
}) => AiConfig(
  provider: AiProviderType.openAiResponses,
  endpoint: 'https://$host',
  apiKey: 'sk-resp',
  model: model,
  thinkingEnabled: thinking,
);

http.Response _stream(List<Map<String, Object?>> events) => http.Response(
  [
    for (final e in events) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
  ].join(),
  200,
  headers: const {'content-type': 'text/event-stream'},
);

Map<String, Object?> _done(int index, Map<String, Object?> item) => {
  'type': 'response.output_item.done',
  'output_index': index,
  'item': item,
};

Map<String, Object?> _completed({
  String status = 'completed',
  Map<String, Object?>? incomplete,
}) => {
  'type': status == 'completed' ? 'response.completed' : 'response.incomplete',
  'response': {
    'status': status,
    'incomplete_details': ?incomplete,
    'usage': {
      'input_tokens': 50,
      'output_tokens': 20,
      'output_tokens_details': {'reasoning_tokens': 12},
    },
  },
};

void main() {
  test('the body is stateless and declares loose tools', () async {
    late http.Request seen;
    await OpenAiResponsesProvider(
      _config('body.example'),
      client: MockClient((request) async {
        seen = request;
        return _stream([
          _done(0, {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'hi'},
            ],
          }),
          _completed(),
        ]);
      }),
    ).chat(
      messages: const [SystemMessage('rules'), UserMessage('u')],
      tools: const [
        ToolDefinition(name: 'f', description: 'd', parameters: {}),
      ],
    );
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(seen.url.toString(), 'https://body.example/v1/responses');
    expect(seen.headers['Authorization'], 'Bearer sk-resp');
    expect(body['store'], isFalse);
    expect(body['instructions'], 'rules');
    expect(body['include'], ['reasoning.encrypted_content']);
    expect((body['tools'] as List).single, containsPair('strict', false));
    expect(body['input'], [
      {'role': 'user', 'content': 'u'},
    ]);
  });

  test('instructions go out empty when there is no system message', () async {
    // The frame-vision request is a lone user message; a relay that finds
    // `instructions` missing fills it with its own prompt.
    late Map<String, dynamic> sent;
    final provider = OpenAiResponsesProvider(
      _config('no-system.example'),
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _stream([_completed()]);
      }),
    );
    final preview = await provider.previewRequest(
      messages: const [UserMessage('frames')],
      tools: const [],
    );
    expect(preview.body, containsPair('instructions', ''));

    await provider.chat(
      messages: const [UserMessage('frames')],
      tools: const [],
    );
    expect(sent, containsPair('instructions', ''));
  });

  test('finished items are the truth: calls, text, reasoning, usage', () async {
    final result = await OpenAiResponsesProvider(
      _config('items.example'),
      client: MockClient(
        (_) async => _stream([
          {
            'type': 'response.output_text.delta',
            'output_index': 1,
            'delta': 'ignored delta',
          },
          _done(0, {
            'type': 'reasoning',
            'id': 'rs_1',
            'encrypted_content': 'opaque',
          }),
          _done(1, {
            'type': 'function_call',
            'call_id': 'call_9',
            'name': 'submit',
            'arguments': '{"g": 1}',
          }),
          _completed(),
        ]),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);

    expect(result.toolCalls.single.id, 'call_9');
    expect(result.toolCalls.single.decodedArguments, {'g': 1});
    expect(result.reasoned, isTrue);
    expect(result.promptTokens, 50);
    expect(result.completionTokens, 20);
    expect(result.raw!.parts, hasLength(2));
  });

  test('the turn and its results go back as items', () {
    final input = OpenAiResponsesProvider.input(const [
      UserMessage('u'),
      AssistantMessage(
        toolCalls: [ToolCall(id: 'call_9', name: 'f', arguments: '{}')],
        raw: ProviderTurn(
          protocol: AiProviderType.openAiResponses,
          model: 'gpt-5.4',
          parts: [
            {'type': 'reasoning', 'encrypted_content': 'opaque'},
            {
              'type': 'function_call',
              'call_id': 'call_9',
              'name': 'f',
              'arguments': '{}',
            },
          ],
        ),
      ),
      ToolResultMessage(toolCallId: 'call_9', name: 'f', content: 'done'),
    ], model: 'gpt-5.4');

    expect(input[1], containsPair('encrypted_content', 'opaque'));
    expect(input.last, {
      'type': 'function_call_output',
      'call_id': 'call_9',
      'output': 'done',
    });
  });

  test(
    'max_output_tokens is a cut-off answer, content_filter a blocked one',
    () async {
      final cut = await OpenAiResponsesProvider(
        _config('cut.example'),
        client: MockClient(
          (_) async => _stream([
            _completed(
              status: 'incomplete',
              incomplete: {'reason': 'max_output_tokens'},
            ),
          ]),
        ),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(cut.truncated, isTrue);

      await expectLater(
        OpenAiResponsesProvider(
          _config('filter.example'),
          client: MockClient(
            (_) async => _stream([
              _completed(
                status: 'incomplete',
                incomplete: {'reason': 'content_filter'},
              ),
            ]),
          ),
        ).chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiException>()),
      );
    },
  );

  group('a stream with no terminal event', () {
    Future<ChatResult> read(String host, String body) =>
        OpenAiResponsesProvider(
          _config(host),
          client: MockClient(
            (_) async => http.Response(
              body,
              200,
              headers: const {'content-type': 'text/event-stream'},
            ),
          ),
        ).chat(messages: const [UserMessage('u')], tools: const []);
    String events(List<Map<String, Object?>> list) => [
      for (final e in list) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
    ].join();
    final message = _done(0, {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': 'whole'},
      ],
    });

    test('is an answer when its items arrived whole', () async {
      // A relay that drops the last event.
      final result = await read('no-terminal.example', events([message]));
      expect(result.text, 'whole');
      expect(result.finishReason, isNull);
    });

    test('is an answer when it holds a finished call', () async {
      final result = await read(
        'no-terminal-call.example',
        events([
          _done(0, {
            'type': 'function_call',
            'call_id': 'c1',
            'name': 'f',
            'arguments': '{}',
          }),
        ]),
      );
      expect(result.toolCalls.single.name, 'f');
    });

    test('is not an answer with nothing finished in it', () async {
      // Cut mid-item: only deltas arrived.
      await expectLater(
        read(
          'no-terminal-delta.example',
          events([
            {
              'type': 'response.output_text.delta',
              'output_index': 0,
              'delta': 'half',
            },
          ]),
        ),
        throwsA(isA<AiNetworkException>()),
      );
      // Reasoning alone is not an answer either.
      await expectLater(
        read(
          'no-terminal-reasoning.example',
          events([
            _done(0, {'type': 'reasoning', 'encrypted_content': 'x'}),
          ]),
        ),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('is not an answer when an item it began never finished', () async {
      // A finished message, then a call cut off mid-arguments: taking the
      // message alone would drop the call.
      await expectLater(
        read(
          'no-terminal-cut-call.example',
          events([
            message,
            {
              'type': 'response.output_item.added',
              'output_index': 1,
              'item': {'type': 'function_call', 'name': 'f'},
            },
            {
              'type': 'response.function_call_arguments.delta',
              'output_index': 1,
              'delta': '{"a": ',
            },
          ]),
        ),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('reports a finished refusal as one', () async {
      await expectLater(
        read(
          'no-terminal-refusal.example',
          events([
            _done(0, {
              'type': 'message',
              'content': [
                {'type': 'refusal', 'refusal': 'no'},
              ],
            }),
          ]),
        ),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('refused'),
          ),
        ),
      );
    });

    test('is marked in the request log', () async {
      final dir = await Directory.systemTemp.createTemp('responses_log');
      addTearDown(() async {
        ApiLog.instance
          ..enabled = false
          ..directory = null;
        await dir.delete(recursive: true);
      });
      ApiLog.instance
        ..directory = dir
        ..enabled = true;

      await read('logged-no-terminal.example', events([message]));
      await read('logged-terminal.example', events([message, _completed()]));
      await ApiLog.instance.flush();

      final lines = (await ApiLog.instance.currentFile!.readAsLines())
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      expect(lines, hasLength(2));
      expect(lines[0]['response']['incomplete_stream'], isTrue);
      expect(
        (lines[1]['response'] as Map).containsKey('incomplete_stream'),
        isFalse,
      );
    });

    test('is not an answer when an event was skipped', () async {
      await expectLater(
        read(
          'no-terminal-skipped.example',
          '${events([message])}data: {"type": "response.output_item\n\n',
        ),
        throwsA(isA<AiNetworkException>()),
      );
    });
  });

  test('a skipped item is taken from the terminal event\'s copy', () async {
    final whole = {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': 'from the terminal'},
      ],
    };
    final terminal = _completed();
    (terminal['response'] as Map)['output'] = [whole];
    final result = await OpenAiResponsesProvider(
      _config('skipped-item.example'),
      client: MockClient(
        (_) async => http.Response(
          'data: {"type": "response.output_item.done", "item": \n\n'
          'data: ${jsonEncode(terminal)}\n\n',
          200,
          headers: const {'content-type': 'text/event-stream'},
        ),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(result.text, 'from the terminal');

    // With no copy to fall back on, the skipped event may have been the
    // answer.
    await expectLater(
      OpenAiResponsesProvider(
        _config('skipped-no-copy.example'),
        client: MockClient(
          (_) async => http.Response(
            'data: {"type": "response.output_item.done", "item": \n\n'
            'data: ${jsonEncode(_completed())}\n\n',
            200,
            headers: const {'content-type': 'text/event-stream'},
          ),
        ),
      ).chat(messages: const [UserMessage('u')], tools: const []),
      throwsA(isA<AiNetworkException>()),
    );
  });

  test(
    'a reasoning model refusing temperature is asked again without it',
    () async {
      final bodies = <Map<String, dynamic>>[];
      await OpenAiResponsesProvider(
        _config('refuse.example'),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          return body.containsKey('temperature')
              ? http.Response(
                  jsonEncode({
                    'error': {
                      'message':
                          "Unsupported parameter: 'temperature' is not supported "
                          'with this model.',
                    },
                  }),
                  400,
                )
              : _stream([_completed()]);
        }),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('temperature'), isFalse);
    },
  );

  group('reasoning', () {
    Future<Map<String, dynamic>> sent(AiConfig config) async {
      late Map<String, dynamic> body;
      await OpenAiResponsesProvider(
        config,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _stream([_completed()]);
        }),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      return body;
    }

    test('off asks for none, on asks for medium', () async {
      // Left out, it ran at the model's own default: medium on GPT-5.5/5.6,
      // high on Grok (KB 03 §7.1).
      expect((await sent(_config('effort-off.example')))['reasoning'], {
        'effort': 'none',
      });
      expect(
        (await sent(_config('effort-on.example', thinking: true)))['reasoning'],
        {'effort': 'medium'},
      );
    });

    test(
      'a refused none goes back to the default, and on still asks',
      () async {
        final bodies = <Map<String, dynamic>>[];
        MockClient client() => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (bodies.length > 8) throw StateError('runaway retries');
          return (body['reasoning'] as Map?)?['effort'] == 'none'
              ? http.Response(
                  jsonEncode({
                    'error': {
                      'message':
                          "Unsupported value: 'reasoning.effort' does not "
                          "support 'none' with this model.",
                      'param': 'reasoning.effort',
                    },
                  }),
                  400,
                )
              : _stream([_completed()]);
        });

        final off = OpenAiResponsesProvider(
          _config('effort-refused.example'),
          client: client(),
        );
        await off.chat(messages: const [UserMessage('u')], tools: const []);
        expect(bodies, hasLength(2));
        expect(bodies.last.containsKey('reasoning'), isFalse);
        expect(off.learned.thinkingOffTried, {LearnedBehaviour.effortNone});
        expect(off.learned.rejectedFields, isNot(contains('reasoning')));

        // Remembered for the route, preview included.
        await off.chat(messages: const [UserMessage('u')], tools: const []);
        expect(bodies, hasLength(3));
        expect(bodies.last.containsKey('reasoning'), isFalse);
        final preview = await off.previewRequest(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        expect(preview.body.containsKey('reasoning'), isFalse);

        // The same route asked for reasoning still asks.
        await OpenAiResponsesProvider(
          _config('effort-refused.example', thinking: true),
          client: client(),
        ).chat(messages: const [UserMessage('u')], tools: const []);
        expect(bodies.last['reasoning'], {'effort': 'medium'});
      },
    );

    test('reasoning refused while on is a refused field', () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = OpenAiResponsesProvider(
        _config('no-reasoning.example', thinking: true),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (bodies.length > 8) throw StateError('runaway retries');
          return body.containsKey('reasoning')
              ? http.Response(
                  jsonEncode({
                    'error': {
                      'message':
                          "Unsupported parameter: 'reasoning' is not "
                          'supported with this model.',
                    },
                  }),
                  400,
                )
              : _stream([_completed()]);
        }),
      );
      await provider.chat(messages: const [UserMessage('u')], tools: const []);
      expect(bodies, hasLength(2));
      expect(provider.learned.rejectedFields, contains('reasoning'));
      expect(provider.learned.thinkingOffTried, isEmpty);
    });

    test(
      'an include refusal quoting its value is not about reasoning',
      () async {
        // `reasoning.encrypted_content` is what `include` asks for; read as
        // naming `reasoning`, it would leave an off model at its default.
        final bodies = <Map<String, dynamic>>[];
        final provider = OpenAiResponsesProvider(
          _config('no-include.example'),
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            bodies.add(body);
            if (bodies.length > 8) throw StateError('runaway retries');
            return body.containsKey('include')
                ? http.Response(
                    jsonEncode({
                      'error': {
                        'message':
                            "Unsupported value: 'reasoning.encrypted_content' "
                            'is not supported with this model.',
                      },
                    }),
                    400,
                  )
                : _stream([_completed()]);
          }),
        );
        await provider.chat(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        expect(bodies, hasLength(2));
        expect(bodies.last['reasoning'], {'effort': 'none'});
        expect(provider.learned.rejectedFields, {'include'});
        expect(provider.learned.thinkingOffTried, isEmpty);
      },
    );
  });

  test('error.param names a refused field the message does not', () async {
    // Audit V5: the message is unverified and constructed here; what is
    // pinned is that `param` is read first.
    final bodies = <Map<String, dynamic>>[];
    final provider = OpenAiResponsesProvider(
      _config('param-include.example', model: 'gpt-4.1'),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (bodies.length > 8) throw StateError('runaway retries');
        return body.containsKey('include')
            ? http.Response(
                jsonEncode({
                  'error': {
                    'message':
                        'Encrypted content is not supported with this model.',
                    'param': 'include',
                  },
                }),
                400,
              )
            : _stream([_completed()]);
      }),
    );
    await provider.chat(messages: const [UserMessage('u')], tools: const []);
    expect(bodies, hasLength(2));
    expect(bodies.last.containsKey('include'), isFalse);
    expect(provider.learned.rejectedFields, {'include'});
  });

  test('error.param outranks a field the message only mentions', () async {
    final bodies = <Map<String, dynamic>>[];
    final provider = OpenAiResponsesProvider(
      const AiConfig(
        provider: AiProviderType.openAiResponses,
        endpoint: 'https://param-first.example',
        apiKey: 'sk-resp',
        model: 'gpt-4.1',
        temperature: 0.7,
        topP: 0.9,
      ),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (bodies.length > 8) throw StateError('runaway retries');
        return body.containsKey('top_p')
            ? http.Response(
                jsonEncode({
                  // Constructed: the message names `temperature` too, and
                  // the field list is tried in order, `temperature` first.
                  'error': {
                    'message': 'top_p is not supported; tune temperature.',
                    'param': 'top_p',
                  },
                }),
                400,
              )
            : _stream([_completed()]);
      }),
    );
    await provider.chat(messages: const [UserMessage('u')], tools: const []);
    expect(bodies, hasLength(2));
    expect(bodies.last['temperature'], 0.7);
    expect(provider.learned.rejectedFields, {'top_p'});
  });

  test('a 404 says where it went', () async {
    final provider = OpenAiResponsesProvider(
      _config('responses-404.example/api'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Not Found'},
          }),
          404,
        ),
      ),
    );
    await expectLater(
      provider.chat(messages: const [UserMessage('u')], tools: const []),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          'HTTP 404: Not Found — POST '
              'https://responses-404.example/api/responses',
        ),
      ),
    );
  });

  test('a param of reasoning.encrypted_content names include', () async {
    // With thinking on, reading it as `reasoning` would drop reasoning.
    final bodies = <Map<String, dynamic>>[];
    final provider = OpenAiResponsesProvider(
      _config('param-encrypted.example', thinking: true),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (bodies.length > 8) throw StateError('runaway retries');
        return body.containsKey('include')
            ? http.Response(
                jsonEncode({
                  'error': {
                    'message': 'Not available for this model.',
                    'param': 'reasoning.encrypted_content',
                  },
                }),
                400,
              )
            : _stream([_completed()]);
      }),
    );
    await provider.chat(messages: const [UserMessage('u')], tools: const []);
    expect(bodies.last.containsKey('include'), isFalse);
    expect(bodies.last['reasoning'], {'effort': 'medium'});
    expect(provider.learned.rejectedFields, {'include'});
  });

  test('a stream that opens with a comment is still a stream', () async {
    final result = await OpenAiResponsesProvider(
      _config('comment.example'),
      client: MockClient(
        (_) async => http.Response(
          ': keep-alive\n\ndata: ${jsonEncode(_completed())}\n\n',
          200,
        ),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(result.finishReason, 'completed');
  });

  test('reasoning without its encrypted content is not sent back', () {
    final input = OpenAiResponsesProvider.input(const [
      AssistantMessage(
        toolCalls: [ToolCall(id: 'c', name: 'f', arguments: '{}')],
        raw: ProviderTurn(
          protocol: AiProviderType.openAiResponses,
          model: 'gpt-5.4',
          parts: [
            {'type': 'reasoning', 'id': 'rs_1'},
            {
              'type': 'function_call',
              'call_id': 'c',
              'name': 'f',
              'arguments': '{}',
            },
          ],
        ),
      ),
    ], model: 'gpt-5.4');
    expect(input.map((i) => i['type']), ['function_call']);
  });

  test('an incomplete response without a reason is no "null" reason', () {
    final result = OpenAiResponsesProvider.parseResponse({
      'status': 'incomplete',
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': 'x'},
          ],
        },
      ],
    }, model: 'm');
    expect(result.finishReason, isNull);
  });

  test('a timed-out generation is sent once, as a timeout', () async {
    for (final (name, answer) in [
      (
        'slow',
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _stream(const []);
        },
      ),
      ('gateway', () async => http.Response('upstream timed out', 504)),
    ]) {
      var calls = 0;
      final provider = OpenAiResponsesProvider(
        _config('$name.example'),
        firstEventTimeout: const Duration(milliseconds: 30),
        client: MockClient((_) {
          calls++;
          return answer();
        }),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiTimeoutException>()),
        reason: name,
      );
      expect(calls, 1, reason: name);
    }
  });

  test('a failed response settles nothing', () {
    expect(
      () => OpenAiResponsesProvider.parseResponse({
        'status': 'failed',
      }, model: 'm'),
      throwsA(isA<AiNetworkException>()),
    );
  });

  test('a failed response with its error still settles nothing', () {
    // What a real `response.failed` looks like: it always carries `error`.
    expect(
      () => OpenAiResponsesProvider.parseResponse({
        'status': 'failed',
        'error': {'code': 'server_error', 'message': 'boom'},
      }, model: 'm'),
      throwsA(isA<AiNetworkException>()),
    );
  });

  test('a server error event mid-stream settles nothing', () {
    expect(
      OpenAiResponsesProvider.streamError({
        'type': 'error',
        'code': 'server_error',
        'message': 'boom',
      }),
      isA<AiNetworkException>(),
    );
    expect(
      OpenAiResponsesProvider.streamError({
        'type': 'error',
        'code': 'invalid_request_error',
        'message': 'bad',
        'param': 'tools',
      }),
      isNot(isA<AiNetworkException>()),
    );
  });

  test('an image goes as an input_image data URL', () {
    final input = OpenAiResponsesProvider.input([
      UserMessage(
        'look',
        images: [
          ImagePart(bytes: Uint8List.fromList([1, 2, 3])),
        ],
      ),
    ], model: 'm');
    final content = input.single['content'] as List;
    expect(content.last, {
      'type': 'input_image',
      'image_url': 'data:image/jpeg;base64,AQID',
      'detail': 'auto',
    });
  });

  // A real round trip, for checking the adapter against the live API after
  // a protocol change. Skipped unless OPENAI_API_KEY is set, so the normal suite
  // never spends money or needs a network.
  test(
    'live: a tool call and its result round-trip',
    () async {
      final config = AiConfig(
        provider: AiProviderType.openAiResponses,
        endpoint:
            Platform.environment['OPENAI_BASE_URL'] ?? 'https://api.openai.com',
        apiKey: Platform.environment['OPENAI_API_KEY']!,
        model: Platform.environment['OPENAI_RESPONSES_MODEL'] ?? 'gpt-5.4-mini',
        maxOutputTokens: 1024,
      );
      const tool = ToolDefinition(
        name: 'report_greeting',
        description: 'Reports a short greeting.',
        parameters: {
          'type': 'object',
          'properties': {
            'greeting': {'type': 'string'},
          },
          'required': ['greeting'],
        },
      );
      final messages = <ChatMessage>[
        const SystemMessage('Call report_greeting with a short greeting.'),
        const UserMessage('Hello!'),
      ];
      final first = await OpenAiResponsesProvider(
        config,
      ).chat(messages: messages, tools: const [tool]);
      expect(first.toolCalls, isNotEmpty);
      messages
        ..add(first.toMessage())
        ..add(
          ToolResultMessage(
            toolCallId: first.toolCalls.first.id,
            name: tool.name,
            content: 'received',
          ),
        );
      // The second turn is where a broken pass-back is refused.
      final second = await OpenAiResponsesProvider(
        config,
      ).chat(messages: messages, tools: const [tool]);
      expect(second.promptTokens, greaterThan(0));
    },
    skip: Platform.environment['OPENAI_API_KEY'] == null
        ? 'set OPENAI_API_KEY to run against the live API'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
