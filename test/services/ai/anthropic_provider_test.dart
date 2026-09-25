import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/anthropic_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/thinking_dialect.dart';

AiConfig _config(
  String endpoint, {
  String model = 'claude-sonnet-5',
  bool thinking = false,
  int? maxOutput,
}) => AiConfig(
  provider: AiProviderType.anthropic,
  endpoint: endpoint,
  apiKey: 'sk-ant-secret',
  model: model,
  thinkingEnabled: thinking,
  maxOutputTokens: maxOutput,
);

String _sse(List<Map<String, Object?>> events) => [
  for (final e in events) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n',
].join();

http.Response _stream(List<Map<String, Object?>> events) => http.Response(
  _sse(events),
  200,
  headers: const {'content-type': 'text/event-stream'},
);

/// A complete streamed reply: [blocks] as content blocks, then the stop.
List<Map<String, Object?>> _reply(
  List<Map<String, Object?>> blocks, {
  String stop = 'end_turn',
  bool terminated = true,
}) => [
  {
    'type': 'message_start',
    'message': {
      'usage': {
        'input_tokens': 10,
        'cache_creation_input_tokens': 5,
        'cache_read_input_tokens': 100,
        'output_tokens': 1,
      },
    },
  },
  for (final (i, block) in blocks.indexed) ...[
    {'type': 'content_block_start', 'index': i, 'content_block': block},
    {'type': 'content_block_stop', 'index': i},
  ],
  {
    'type': 'message_delta',
    'delta': {'stop_reason': stop},
    'usage': {'output_tokens': 42},
  },
  if (terminated) {'type': 'message_stop'},
];

void main() {
  group('address and headers', () {
    Future<http.BaseRequest> sent(String endpoint) async {
      late http.BaseRequest seen;
      await AnthropicProvider(
        _config(endpoint),
        client: MockClient((request) async {
          seen = request;
          return _stream(
            _reply([
              {'type': 'text', 'text': 'hi'},
            ]),
          );
        }),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      return seen;
    }

    test('/v1/messages goes under the root or a mirror prefix', () async {
      expect(
        (await sent('https://api.anthropic.com')).url.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        (await sent(
          'https://dashscope.aliyuncs.com/apps/anthropic/',
        )).url.toString(),
        'https://dashscope.aliyuncs.com/apps/anthropic/v1/messages',
      );
      expect(
        (await sent('https://relay.example.com/v1')).url.toString(),
        'https://relay.example.com/v1/messages',
      );
    });

    test('the key goes in x-api-key with a pinned version', () async {
      final request = await sent('https://api.anthropic.com');
      expect(request.headers['x-api-key'], 'sk-ant-secret');
      expect(
        request.headers['anthropic-version'],
        AnthropicProvider.apiVersion,
      );
      expect(request.headers.containsKey('Authorization'), isFalse);
    });
  });

  test('the conversation is repaired into alternating turns', () {
    final wire = AnthropicProvider.wire(const [
      SystemMessage('sys'),
      UserMessage('a'),
      UserMessage('b'),
      AssistantMessage(
        content: 'calling',
        toolCalls: [
          ToolCall(id: 't1', name: 'f', arguments: '{"x": 1}'),
          ToolCall(id: 't2', name: 'f', arguments: '{}'),
        ],
      ),
      ToolResultMessage(toolCallId: 't1', name: 'f', content: 'one'),
      ToolResultMessage(toolCallId: 't2', name: 'f', content: 'two'),
      UserMessage('next'),
    ], model: 'm');

    expect(wire.map((m) => m['role']), ['user', 'assistant', 'user']);
    expect(wire[0]['content'], hasLength(2));
    final calls = wire[1]['content'] as List;
    expect((calls[1] as Map)['type'], 'tool_use');
    expect((calls[1] as Map)['input'], {'x': 1});
    // Both results, then the next user text, in one user turn.
    final results = wire[2]['content'] as List;
    expect(results.map((b) => (b as Map)['type']), [
      'tool_result',
      'tool_result',
      'text',
    ]);
  });

  test(
    'the body carries system, a required max_tokens and tool schemas',
    () async {
      late Map<String, dynamic> body;
      await AnthropicProvider(
        _config('https://body.example'),
        client: MockClient((request) async {
          body = jsonDecode(request.body);
          return _stream(
            _reply([
              {'type': 'text', 'text': 'ok'},
            ]),
          );
        }),
      ).chat(
        messages: const [SystemMessage('be brief'), UserMessage('u')],
        tools: const [
          ToolDefinition(
            name: 'f',
            description: 'd',
            parameters: {'type': 'object'},
          ),
        ],
      );
      expect(body['system'], 'be brief');
      expect(body['max_tokens'], AnthropicProvider.defaultMaxTokens);
      expect((body['tools'] as List).single, {
        'name': 'f',
        'description': 'd',
        'input_schema': {'type': 'object'},
      });
      expect(body.containsKey('thinking'), isFalse);
    },
  );

  group('thinking', () {
    Future<Map<String, dynamic>> sent(
      String endpoint, {
      String model = 'claude-sonnet-5',
    }) async {
      late Map<String, dynamic> body;
      await AnthropicProvider(
        _config(endpoint, model: model, thinking: true, maxOutput: 16000),
        client: MockClient((request) async {
          body = jsonDecode(request.body);
          return _stream(
            _reply([
              {'type': 'text', 'text': 'ok'},
            ]),
          );
        }),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      return body;
    }

    test('Claude 4.6 on asks adaptive, and no sampling', () async {
      final body = await sent('https://thinking.example');
      // Not Anthropic's own host: no `display`, which mirrors do not document.
      expect(body['thinking'], {'type': 'adaptive'});
      expect(body.containsKey('temperature'), isFalse);
    });

    test("Anthropic's own host also asks for the summary", () async {
      final adaptive = await sent('https://api.anthropic.com');
      expect(adaptive['thinking'], {
        'type': 'adaptive',
        'display': 'summarized',
      });
      final extended = await sent(
        'https://api.anthropic.com',
        model: 'claude-sonnet-4-5',
      );
      expect(extended['thinking'], {
        'type': 'enabled',
        'budget_tokens': 8000,
        'display': 'summarized',
      });
    });

    test('an earlier Claude or a mirror model gets a budget', () async {
      final body = await sent('https://budget.example', model: 'glm-4.7');
      expect(body['thinking'], {'type': 'enabled', 'budget_tokens': 8000});
      expect(body.containsKey('temperature'), isFalse);
    });

    test('the form follows the Claude generation', () {
      const expected = {
        'claude-sonnet-4-5': MessagesThinking.extended,
        'claude-sonnet-4-5-20250929': MessagesThinking.extended,
        'claude-opus-4-20250514': MessagesThinking.extended,
        'claude-3-7-sonnet-20250219': MessagesThinking.extended,
        'claude-haiku-4-5-20251001': MessagesThinking.extended,
        'claude-opus-4-6': MessagesThinking.adaptive,
        'claude-sonnet-4-6-20260101': MessagesThinking.adaptive,
        'anthropic/claude-sonnet-4.6': MessagesThinking.adaptive,
        'claude-sonnet-5': MessagesThinking.adaptive,
        'claude-opus-5-5': MessagesThinking.adaptive,
        'claude-fable-5-1': MessagesThinking.adaptive,
        // Legacy, Vertex, Bedrock and relay spellings.
        'claude-3-5-sonnet-latest': MessagesThinking.extended,
        'claude-4-opus': MessagesThinking.extended,
        'claude-sonnet-4-5@20250929': MessagesThinking.extended,
        'anthropic.claude-sonnet-4-5-20250929-v1:0': MessagesThinking.extended,
        'us.anthropic.claude-opus-4-6-v1': MessagesThinking.adaptive,
        'claude-3-7-sonnet-20250219-thinking': MessagesThinking.extended,
        'glm-4.7': MessagesThinking.extended,
        'deepseek-v4': MessagesThinking.extended,
        'MiniMax-M3': MessagesThinking.extended,
      };
      for (final MapEntry(key: model, value: form) in expected.entries) {
        expect(MessagesThinking.forModel(model), form, reason: model);
      }
    });

    /// A route that refuses [refuse] forms with [message]; the bodies sent.
    Future<(List<Map<String, dynamic>>, AnthropicProvider)> refusing(
      String host,
      Set<String> refuse,
      String Function(String type) message, {
      String model = 'claude-opus-4-6',
    }) async {
      final bodies = <Map<String, dynamic>>[];
      final provider = AnthropicProvider(
        _config('https://$host', model: model, thinking: true),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (bodies.length > 8) throw StateError('runaway retries');
          final type = (body['thinking'] as Map?)?['type'] as String?;
          return type != null && refuse.contains(type)
              ? http.Response(
                  jsonEncode({
                    'type': 'error',
                    'error': {
                      'type': 'invalid_request_error',
                      'message': message(type),
                    },
                  }),
                  400,
                )
              : _stream(
                  _reply([
                    {'type': 'text', 'text': 'ok'},
                  ]),
                );
        }),
      );
      await provider.chat(messages: const [UserMessage('u')], tools: const []);
      return (bodies, provider);
    }

    test('a refused form is swapped for the other, not given up', () async {
      // An older model's answer to adaptive names the field without refusing
      // thinking; reading it as a refusal switched reasoning off for a month.
      final (bodies, provider) = await refusing(
        'swap.example',
        {'adaptive'},
        (type) =>
            "thinking.type: Input tag '$type' found using 'type' does not "
            "match any of the expected tags: 'disabled', 'enabled'",
      );
      expect(bodies, hasLength(2));
      expect(bodies.first['thinking'], {'type': 'adaptive'});
      expect((bodies.last['thinking'] as Map)['type'], 'enabled');
      expect(provider.learned.rejectedFields, {'thinking:adaptive'});

      // Remembered: the next request asks in the form that worked.
      await provider.chat(messages: const [UserMessage('u')], tools: const []);
      expect(bodies, hasLength(3));
      expect((bodies.last['thinking'] as Map)['type'], 'enabled');
    });

    test('thinking is given up only once both forms are refused', () async {
      final (bodies, provider) = await refusing('no-thinking.example', {
        'adaptive',
        'enabled',
      }, (_) => 'thinking: Extra inputs are not permitted');
      expect(bodies, hasLength(3));
      expect(bodies.last.containsKey('thinking'), isFalse);
      expect(
        provider.learned.rejectedFields,
        containsAll(['thinking:adaptive', 'thinking:enabled', 'thinking']),
      );
    });

    test(
      'the other form refused without refusing thinking is thrown',
      () async {
        // Both forms named, neither refused as a feature: giving thinking up
        // here would be the silent month-long switch-off again.
        final bodies = <Map<String, dynamic>>[];
        final provider = AnthropicProvider(
          _config(
            'https://tag-mismatch.example',
            model: 'claude-opus-4-6',
            thinking: true,
          ),
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            bodies.add(body);
            final type = (body['thinking'] as Map?)?['type'];
            return http.Response(
              jsonEncode({
                'type': 'error',
                'error': {
                  'type': 'invalid_request_error',
                  'message':
                      "thinking.type: Input tag '$type' found using 'type' "
                      'does not match any of the expected tags',
                },
              }),
              400,
            );
          }),
        );
        await expectLater(
          provider.chat(messages: const [UserMessage('u')], tools: const []),
          throwsA(isA<AiException>()),
        );
        expect(bodies, hasLength(2));
        expect(provider.learned.rejectedFields, {'thinking:adaptive'});
      },
    );

    test('a budget error is about the numbers, not the form', () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = AnthropicProvider(
        _config(
          'https://budget-error.example',
          model: 'claude-sonnet-4-5',
          thinking: true,
        ),
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'type': 'error',
              'error': {
                'type': 'invalid_request_error',
                'message':
                    '`max_tokens` must be greater than '
                    '`thinking.budget_tokens`',
              },
            }),
            400,
          );
        }),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiException>()),
      );
      expect(bodies, hasLength(1));
      expect(provider.learned.rejectedFields, isEmpty);
    });

    // Errors that say "thinking" without refusing either form: each is
    // thrown on the first request, and nothing is learned from it.
    for (final (i, (name, model, message)) in [
      (
        'about the thinking blocks in the history',
        'claude-opus-4-6',
        'messages.1.content.0: `thinking` or `redacted_thinking` blocks in '
            'the latest assistant message cannot be modified',
      ),
      (
        'about a thinking block bound to another conversation',
        'claude-opus-4-6',
        'messages.3.content.0: Invalid `signature` in `thinking` block. The '
            'block is bound to a different conversation.',
      ),
      (
        'naming a relay model whose id says thinking',
        'claude-3-7-sonnet-20250219-thinking',
        'model claude-3-7-sonnet-20250219-thinking is not supported',
      ),
    ].indexed) {
      test('an error $name is thrown, not learned', () async {
        final bodies = <Map<String, dynamic>>[];
        final provider = AnthropicProvider(
          _config(
            'https://not-a-refusal-$i.example',
            model: model,
            thinking: true,
          ),
          client: MockClient((request) async {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'type': 'error',
                'error': {'type': 'invalid_request_error', 'message': message},
              }),
              400,
            );
          }),
        );
        await expectLater(
          provider.chat(messages: const [UserMessage('u')], tools: const []),
          throwsA(isA<AiException>()),
        );
        expect(bodies, hasLength(1));
        expect(provider.learned.rejectedFields, isEmpty);
      });
    }
  });

  group('the stream', () {
    test('assembles text, tool input fragments and thinking', () async {
      final events = [
        {
          'type': 'message_start',
          'message': {
            'usage': {
              'input_tokens': 10,
              'cache_creation_input_tokens': 5,
              'cache_read_input_tokens': 100,
            },
          },
        },
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'thinking', 'thinking': ''},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'sig'},
        },
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'submit',
            'input': <String, Object?>{},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"a": '},
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '1}'},
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 42},
        },
        {'type': 'message_stop'},
      ];
      final result = await AnthropicProvider(
        _config('https://stream.example'),
        client: MockClient((_) async => _stream(events)),
      ).chat(messages: const [UserMessage('u')], tools: const []);

      expect(result.toolCalls.single.name, 'submit');
      expect(result.toolCalls.single.decodedArguments, {'a': 1});
      expect(result.reasoned, isTrue);
      // Input, cache writes and cache reads together are the prompt.
      expect(result.promptTokens, 115);
      expect(result.completionTokens, 42);
      final thinking = result.raw!.parts.first as Map;
      expect(thinking['signature'], 'sig');
      expect(result.truncated, isFalse);
    });

    test('the turn goes back verbatim only to the same model', () {
      final turn = AssistantMessage(
        toolCalls: const [ToolCall(id: 't', name: 'f', arguments: '{}')],
        raw: const ProviderTurn(
          protocol: AiProviderType.anthropic,
          model: 'claude-a',
          parts: [
            {'type': 'thinking', 'thinking': 'x', 'signature': 's'},
            {'type': 'tool_use', 'id': 't', 'name': 'f', 'input': {}},
          ],
        ),
      );
      final same = AnthropicProvider.wire([turn], model: 'claude-a');
      final other = AnthropicProvider.wire([turn], model: 'claude-b');
      expect(
        (same.single['content'] as List).first,
        containsPair('type', 'thinking'),
      );
      expect(
        (other.single['content'] as List).single,
        containsPair('type', 'tool_use'),
      );
    });

    test('max_tokens is a cut-off answer', () async {
      final result = await AnthropicProvider(
        _config('https://cut.example'),
        client: MockClient(
          (_) async => _stream(
            _reply([
              {'type': 'text', 'text': 'part'},
            ], stop: 'max_tokens'),
          ),
        ),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(result.truncated, isTrue);
    });

    test('a refusal throws', () async {
      await expectLater(
        AnthropicProvider(
          _config('https://refusal.example'),
          client: MockClient(
            (_) async => _stream(
              _reply([
                {'type': 'text', 'text': 'no'},
              ], stop: 'refusal'),
            ),
          ),
        ).chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiException>()),
      );
    });

    test('a stream without message_stop is not an answer', () async {
      await expectLater(
        AnthropicProvider(
          _config('https://cutoff.example'),
          client: MockClient(
            (_) async => _stream(
              _reply([
                {'type': 'text', 'text': 'half'},
              ], terminated: false),
            ),
          ),
        ).chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('an overloaded error mid-stream settles nothing', () async {
      await expectLater(
        AnthropicProvider(
          _config('https://overloaded.example'),
          client: MockClient(
            (_) async => _stream([
              {
                'type': 'error',
                'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
              },
            ]),
          ),
        ).chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiNetworkException>()),
      );
    });
  });

  test('a refused optional field is dropped and remembered', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      return body.containsKey('temperature')
          ? http.Response(
              jsonEncode({
                'type': 'error',
                'error': {
                  'message': 'temperature: Extra inputs are not permitted',
                },
              }),
              400,
            )
          : _stream(
              _reply([
                {'type': 'text', 'text': 'ok'},
              ]),
            );
    });
    final config = _config('https://refused.example');
    await AnthropicProvider(
      config,
      client: client,
    ).chat(messages: const [UserMessage('u')], tools: const []);
    await AnthropicProvider(
      config,
      client: client,
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(bodies, hasLength(3));
    expect(bodies.last.containsKey('temperature'), isFalse);
  });

  test('a stream that opens with a comment is still a stream', () async {
    final result = await AnthropicProvider(
      _config('https://comment.example'),
      client: MockClient(
        (_) async => http.Response(
          ': OPENROUTER PROCESSING\n\n${_sse(_reply([
            {'type': 'text', 'text': 'hi'},
          ]))}',
          200,
        ),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(result.text, 'hi');
  });

  test('usage reported only at the end is still counted', () async {
    final result = await AnthropicProvider(
      _config('https://late-usage.example'),
      client: MockClient(
        (_) async => _stream([
          {
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 0},
            },
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': 'x'},
          },
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'input_tokens': 30, 'output_tokens': 4},
          },
          {'type': 'message_stop'},
        ]),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(result.promptTokens, 30);
    expect(result.completionTokens, 4);
  });

  test('a cut-off tool input keeps its thinking block', () async {
    final result = await AnthropicProvider(
      _config('https://cut-tool.example', thinking: true),
      client: MockClient(
        (_) async => _stream([
          {
            'type': 'message_start',
            'message': {'usage': <String, Object?>{}},
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'thinking',
              'thinking': 't',
              'signature': 's',
            },
          },
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'f',
              'input': <String, Object?>{},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': '{"a": '},
          },
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'max_tokens'},
          },
          {'type': 'message_stop'},
        ]),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);

    expect(result.truncated, isTrue);
    expect(result.toolCalls.single.decodedArguments, isNull);
    final parts = result.raw!.parts;
    expect((parts.first as Map)['type'], 'thinking');
    expect((parts[1] as Map)['input'], <String, Object?>{});
  });

  test('a refusal of thinking is told apart from the budget rule', () {
    expect(
      AnthropicProvider.refusesThinking(
        'http 400: thinking: extra inputs are not permitted',
      ),
      isTrue,
    );
    expect(
      AnthropicProvider.refusesThinking(
        'http 400: this model does not support thinking',
      ),
      isTrue,
    );
    expect(
      AnthropicProvider.refusesThinking(
        'http 400: max_tokens must be greater than thinking.budget_tokens',
      ),
      isFalse,
    );
  });

  test('a mirror also gets the key as a bearer token', () async {
    late http.BaseRequest seen;
    await AnthropicProvider(
      _config('https://open.bigmodel.cn/api/anthropic'),
      client: MockClient((request) async {
        seen = request;
        return _stream(
          _reply([
            {'type': 'text', 'text': 'ok'},
          ]),
        );
      }),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(seen.headers['Authorization'], 'Bearer sk-ant-secret');
    expect(seen.headers['x-api-key'], 'sk-ant-secret');
  });

  test('an image goes as a base64 image block before the text', () {
    final wire = AnthropicProvider.wire([
      UserMessage(
        'look',
        images: [
          ImagePart(bytes: Uint8List.fromList([1, 2, 3])),
        ],
      ),
    ], model: 'm');
    final blocks = wire.single['content'] as List;
    expect(blocks.first, {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': 'AQID'},
    });
    expect((blocks.last as Map)['text'], 'look');
  });

  // A real round trip, for checking the adapter against the live API after
  // a protocol change. Skipped unless ANTHROPIC_API_KEY is set, so the normal suite
  // never spends money or needs a network.
  test(
    'live: a tool call and its result round-trip',
    () async {
      final config = AiConfig(
        provider: AiProviderType.anthropic,
        endpoint:
            Platform.environment['ANTHROPIC_BASE_URL'] ??
            'https://api.anthropic.com',
        apiKey: Platform.environment['ANTHROPIC_API_KEY']!,
        model: Platform.environment['ANTHROPIC_MODEL'] ?? 'claude-sonnet-5',
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
      final first = await AnthropicProvider(
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
      final second = await AnthropicProvider(
        config,
      ).chat(messages: messages, tools: const [tool]);
      expect(second.promptTokens, greaterThan(0));
    },
    skip: Platform.environment['ANTHROPIC_API_KEY'] == null
        ? 'set ANTHROPIC_API_KEY to run against the live API'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
