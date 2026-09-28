import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/anthropic_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';
import 'package:jellyfin_media_management_tool/services/ai/messages_refusal.dart';
import 'package:jellyfin_media_management_tool/services/ai/thinking_dialect.dart';

import '../../helpers/http.dart';

AiConfig _config(
  String endpoint, {
  String model = 'claude-sonnet-5',
  bool thinking = false,
  int? maxOutput,
  double? temperature,
  double? topP,
  int? topK,
}) => AiConfig(
  provider: AiProviderType.anthropic,
  endpoint: endpoint,
  apiKey: 'sk-ant-secret',
  model: model,
  thinkingEnabled: thinking,
  maxOutputTokens: maxOutput,
  temperature: temperature,
  topP: topP,
  topK: topK,
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

    test('a pasted full endpoint is cut back to its root', () async {
      expect(
        (await sent('https://api.anthropic.com/v1/messages')).url.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        (await sent(
          'https://dashscope.aliyuncs.com/apps/anthropic/v1/messages/',
        )).url.toString(),
        'https://dashscope.aliyuncs.com/apps/anthropic/v1/messages',
      );
      expect(
        (await sent(
          'https://api.anthropic.com/v1/messages?beta=true',
        )).url.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      // A host is not a path segment.
      expect(
        (await sent('http://messages')).url.toString(),
        'http://messages/v1/messages',
      );
    });

    test('a 404 says where it went, without the user info', () async {
      final provider = AnthropicProvider(
        _config('https://user:pass@wrong-path.example/api/claude'),
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
                'https://wrong-path.example/api/claude/v1/messages',
          ),
        ),
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

    test(
      'a family is asked for the mode it runs in, not the saved one',
      () async {
        // The saved choice is resolved above the adapter. A family that never
        // reasons, saved on, is not asked; one that always reasons, saved off,
        // is — and on a switch route is not told off.
        Future<Map<String, dynamic>> family(
          String endpoint,
          String model, {
          required bool saved,
        }) async {
          late Map<String, dynamic> body;
          await AnthropicProvider(
            _config(endpoint, model: model, thinking: saved, maxOutput: 16000),
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

        const relay = 'https://family.example';
        final never = await family(
          relay,
          'qwen3-30b-a3b-instruct-2507',
          saved: true,
        );
        expect(never.containsKey('thinking'), isFalse);
        expect(never.containsKey('temperature'), isTrue);
        final always = await family(
          relay,
          'qwen3-30b-a3b-thinking-2507',
          saved: false,
        );
        expect(always['thinking'], {'type': 'enabled', 'budget_tokens': 8000});
        expect(always.containsKey('temperature'), isFalse);

        const switchRoute = 'https://api.minimaxi.com/anthropic';
        expect(
          (await family(
            switchRoute,
            'qwen3-30b-a3b-instruct-2507',
            saved: true,
          ))['thinking'],
          {'type': 'disabled'},
        );
        expect(
          (await family(
            switchRoute,
            'qwen3-30b-a3b-thinking-2507',
            saved: false,
          ))['thinking'],
          {'type': 'adaptive'},
        );
      },
    );

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
      bool thinking = true,
    }) async {
      final bodies = <Map<String, dynamic>>[];
      final provider = AnthropicProvider(
        _config('https://$host', model: model, thinking: thinking),
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

    test(
      'a sub-field refused in unknown-field words is the form, swapped',
      () async {
        // A Pydantic server with `extra=forbid` whose model takes only
        // adaptive and disabled: the budget is the extra input, and
        // `thinking.type` is named, so the server knows the field. Giving up
        // every form here would switch reasoning off for a month.
        final (bodies, provider) = await refusing(
          'subfield.example',
          {'enabled'},
          (_) =>
              '2 validation errors for MessagesRequest\nthinking.type\n  Input '
              "should be 'adaptive' or 'disabled' [type=literal_error, "
              "input_value='enabled', input_type=str]\nthinking.budget_tokens\n"
              '  Extra inputs are not permitted [type=extra_forbidden, '
              'input_value=1024, input_type=int]',
          model: 'claude-sonnet-4-5',
        );
        expect(bodies, hasLength(2));
        expect((bodies.first['thinking'] as Map)['type'], 'enabled');
        expect(bodies.last['thinking'], {'type': 'adaptive'});
        expect(provider.learned.rejectedFields, {'thinking:enabled'});
      },
    );

    test('a form refused beside "always thinks" is the form, swapped', () async {
      // "Cannot stop" answers off alone; asked on, the words beside the
      // form name say the form was refused, and the other is tried.
      final (bodies, provider) = await refusing(
        'always-on.example',
        {'adaptive'},
        (type) =>
            "thinking.type: '$type' is not supported; this model always thinks",
        model: 'claude-sonnet-4-6',
      );
      expect(bodies, hasLength(2));
      expect((bodies.last['thinking'] as Map)['type'], 'enabled');
      expect(provider.learned.rejectedFields, {'thinking:adaptive'});
      expect(provider.learned.thinkingOffTried, isEmpty);
    });

    test('a budget out of range is thrown and teaches nothing', () async {
      // The number is the user's to change; remembering the form as
      // refused would fail every request after they did.
      final bodies = <Map<String, dynamic>>[];
      final provider = AnthropicProvider(
        _config(
          'https://budget-cap.example',
          model: 'claude-sonnet-4-5',
          thinking: true,
          maxOutput: 131072,
        ),
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'type': 'error',
              'error': {
                'type': 'invalid_request_error',
                'message':
                    'thinking.budget_tokens\n  Input should be less than or '
                    'equal to 32000 [type=less_than_equal, '
                    'input_value=65536, input_type=int]',
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

    test('a budget refused as an extra input is the form, swapped', () async {
      // A server modelled on `{type}` alone, with extra inputs forbidden:
      // the sub-field named says it knows the field, so adaptive is tried.
      final (bodies, provider) = await refusing(
        'no-budget.example',
        {'enabled'},
        (_) =>
            'thinking.budget_tokens\n  Extra inputs are not permitted '
            '[type=extra_forbidden, input_value=1024, input_type=int]',
        model: 'claude-sonnet-4-5',
      );
      expect(bodies, hasLength(2));
      expect(bodies.last['thinking'], {'type': 'adaptive'});
      expect(provider.learned.rejectedFields, {'thinking:enabled'});
    });

    test(
      'an unrecognized model named after thinking teaches nothing',
      () async {
        // A relay's upstream alias, left over after the model id is taken
        // out: about the model, not the field.
        final bodies = <Map<String, dynamic>>[];
        final provider = AnthropicProvider(
          _config(
            'https://alias.example',
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
                  'message': 'unrecognized model: claude-sonnet-4-5-thinking',
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
      },
    );

    test('a refusal of thinking itself gives up every form', () async {
      // The field is refused, not a form of it: trying the other form would
      // be one more refused request.
      final (bodies, provider) = await refusing('no-thinking.example', {
        'adaptive',
        'enabled',
      }, (_) => 'thinking: Extra inputs are not permitted');
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('thinking'), isFalse);
      expect(
        provider.learned.rejectedFields,
        containsAll(['thinking:adaptive', 'thinking:enabled', 'thinking']),
      );
    });

    test('a relay that refuses thinking under the name it translated it to '
        'gives it up', () async {
      // The relay turned `thinking` into its upstream's field and the
      // upstream refused that name. What the relay sends is not the
      // adapter's to change, so the route is remembered as one that
      // cannot carry a request for thinking — every form and the field —
      // and the next request goes without it, with the family's sampling
      // values, whatever its locked toggle says. Before this, the error
      // named nothing the adapter learned from and every request failed.
      for (final (i, message) in [
        'Unrecognized request argument supplied: reasoning_effort',
        'reasoning_effort\n  Extra inputs are not permitted '
            "[type=extra_forbidden, input_value='medium', input_type=str]",
        "Unknown parameter: 'reasoning_effort'.",
        "Unsupported parameter: 'reasoning_effort' is not supported with "
            'this model.',
        'Unrecognized request argument supplied: chat_template_kwargs',
        'Invalid JSON payload received. Unknown name "thinkingConfig" at '
            "'generation_config': Cannot find field.",
        "'reasoning' is not a valid parameter",
        "Invalid value for 'reasoning_effort': expected one of low, "
            'medium, high',
      ].indexed) {
        final (bodies, provider) = await refusing(
          'translated-$i.example',
          {'adaptive', 'enabled'},
          (_) => message,
          model: 'deepseek-r1-distill-qwen-14b',
          // Saved either way: the family's toggle is locked on.
          thinking: i.isEven,
        );
        expect(bodies, hasLength(2), reason: message);
        expect(bodies.first['thinking'], containsPair('type', 'enabled'));
        expect(bodies.last.containsKey('thinking'), isFalse, reason: message);
        expect(bodies.last['temperature'], 0.6, reason: message);
        expect(provider.learned.rejectedFields, {
          'thinking',
          'thinking:adaptive',
          'thinking:enabled',
        }, reason: message);
        expect(provider.learned.thinkingOffTried, isEmpty);
      }
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

    group('on a platform that takes a switch', () {
      // MiniMax's /anthropic: `adaptive | disabled`, no `display`, no budget.
      Future<Map<String, dynamic>> minimax({required bool thinking}) async {
        late Map<String, dynamic> body;
        await AnthropicProvider(
          _config(
            'https://api.minimaxi.com/anthropic',
            model: 'MiniMax-M3',
            thinking: thinking,
          ),
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

      test('off is sent as disabled, with sampling', () async {
        final body = await minimax(thinking: false);
        expect(body['thinking'], {'type': 'disabled'});
        expect(body.containsKey('temperature'), isTrue);
      });

      test('on is adaptive, with no display or budget', () async {
        final body = await minimax(thinking: true);
        expect(body['thinking'], {'type': 'adaptive'});
      });

      test('DeepSeek, DashScope and Zhipu switch the same way', () async {
        // Their Messages faces think unless told not to (measured
        // 2026-09-28), so off is said in so many words, with the sampling
        // values, and on is `adaptive` — the one form a switch route asks.
        for (final (endpoint, model) in [
          ('https://api.deepseek.com/anthropic', 'deepseek-v4-pro'),
          ('https://dashscope.aliyuncs.com/apps/anthropic', 'qwen3.8-flash'),
          ('https://open.bigmodel.cn/api/anthropic', 'glm-4.6'),
        ]) {
          for (final thinking in [false, true]) {
            late Map<String, dynamic> body;
            await AnthropicProvider(
              _config(
                endpoint,
                model: model,
                thinking: thinking,
                temperature: 0.7,
              ),
              client: MockClient((request) async {
                body = jsonDecode(request.body);
                return _stream(
                  _reply([
                    {'type': 'text', 'text': 'ok'},
                  ]),
                );
              }),
            ).chat(messages: const [UserMessage('u')], tools: const []);
            expect(body['thinking'], {
              'type': thinking ? 'adaptive' : 'disabled',
            }, reason: '$model $thinking');
            expect(body.containsKey('temperature'), !thinking, reason: model);
          }
        }
      });

      test(
        'a model that cannot stop reasoning is not told off again, but asked '
        'for the least',
        () async {
          final bodies = <Map<String, dynamic>>[];
          AnthropicProvider provider() => AnthropicProvider(
            _config(
              'https://always.minimaxi.com/anthropic',
              model: 'MiniMax-M3',
            ),
            client: MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              bodies.add(body);
              if (bodies.length > 8) throw StateError('runaway retries');
              return (body['thinking'] as Map?)?['type'] == 'disabled'
                  ? http.Response.bytes(
                      utf8.encode(
                        jsonEncode({
                          'type': 'error',
                          'error': {
                            'type': 'invalid_request_error',
                            'message': '该模型始终思考，不支持关闭思考',
                          },
                        }),
                      ),
                      400,
                      headers: const {
                        'content-type': 'application/json; charset=utf-8',
                      },
                    )
                  : _stream(
                      _reply([
                        {'type': 'text', 'text': 'ok'},
                      ]),
                    );
            }),
          );
          final first = provider();
          await first.chat(messages: const [UserMessage('u')], tools: const []);
          expect(bodies, hasLength(2));
          expect(bodies.last.containsKey('thinking'), isFalse);
          expect(bodies.last['output_config'], {'effort': 'low'});
          expect(first.learned.thinkingOffTried, {LearnedBehaviour.dialectOff});
          expect(first.learned.rejectedFields, isEmpty);

          // A fresh provider starts from what was learned.
          await provider().chat(
            messages: const [UserMessage('u')],
            tools: const [],
          );
          expect(bodies, hasLength(3));
          expect(bodies.last.containsKey('thinking'), isFalse);
          expect(bodies.last['output_config'], {'effort': 'low'});
          addTearDown(first.forgetLearned);
        },
      );

      /// A switch route with thinking off whose server answers `disabled`
      /// with [message]; the bodies sent and what it learned.
      Future<(List<Map<String, dynamic>>, AnthropicProvider)> offRefused(
        String host,
        String message, {
        String? endpoint,
        String model = 'MiniMax-M3',
      }) async {
        final bodies = <Map<String, dynamic>>[];
        final provider = AnthropicProvider(
          _config(endpoint ?? 'https://$host/anthropic', model: model),
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            bodies.add(body);
            if (bodies.length > 8) throw StateError('runaway retries');
            return body.containsKey('thinking')
                // Bytes, UTF-8 declared: a String body would be Latin-1.
                ? http.Response.bytes(
                    utf8.encode(
                      jsonEncode({
                        'type': 'error',
                        'error': {
                          'type': 'invalid_request_error',
                          'message': message,
                        },
                      }),
                    ),
                    400,
                    headers: const {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  )
                : _stream(
                    _reply([
                      {'type': 'text', 'text': 'ok'},
                    ]),
                  );
          }),
        );
        try {
          await provider.chat(
            messages: const [UserMessage('u')],
            tools: const [],
          );
        } on AiException {
          // Read by the test from the bodies and what was learned.
        }
        return (bodies, provider);
      }

      test('a model told off in the words measured on 2026-09-28 is the '
          'model that cannot stop, once', () async {
        for (final (endpoint, model, message) in [
          // Zhipu's own face, glm-5.3: code 1210, wrapped with the id.
          (
            'https://open.bigmodel.cn/api/anthropic',
            'glm-5.3',
            '[1210][该模型始终思考，不支持关闭思考；请使用 low、high 或 max。]'
                '[202609281155421633d5b34a1644c0]',
          ),
          // DashScope's face for a third-party model, in its own
          // `enable_thinking`.
          (
            'https://dashscope.aliyuncs.com/apps/anthropic',
            'MiniMax-M2.5',
            '<400> InternalError.Algo.InvalidParameter: The value of the '
                'enable_thinking parameter is restricted to True.',
          ),
        ]) {
          final (bodies, provider) = await offRefused(
            '',
            message,
            endpoint: endpoint,
            model: model,
          );
          expect(bodies, hasLength(2), reason: model);
          expect(bodies.first['thinking'], {'type': 'disabled'});
          expect(bodies.first.containsKey('output_config'), isFalse);
          expect(bodies.last.containsKey('thinking'), isFalse, reason: model);
          expect(bodies.last['output_config'], {
            'effort': 'low',
          }, reason: model);
          expect(provider.learned.thinkingOffTried, {
            LearnedBehaviour.dialectOff,
          }, reason: model);
          expect(provider.learned.rejectedFields, isEmpty, reason: model);
          // The next request does not say `disabled` again: it asks for the
          // least.
          final preview = await AnthropicProvider(
            _config(endpoint, model: model),
          ).previewRequest(messages: const [UserMessage('u')], tools: const []);
          expect(preview.body.containsKey('thinking'), isFalse, reason: model);
          expect(preview.body['output_config'], {
            'effort': 'low',
          }, reason: model);
          addTearDown(provider.forgetLearned);
        }
      });

      /// A switch route with thinking off whose server answers `disabled`
      /// with Zhipu's 1210 and the least reasoning with [leastMessage]; the
      /// bodies sent and what it learned.
      Future<(List<Map<String, dynamic>>, AnthropicProvider)> leastRefused(
        String leastMessage,
      ) async {
        final bodies = <Map<String, dynamic>>[];
        http.Response refuse(String message) => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'type': 'error',
              'error': {'type': 'invalid_request_error', 'message': message},
            }),
          ),
          400,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
        final provider = AnthropicProvider(
          _config('https://open.bigmodel.cn/api/anthropic', model: 'glm-5.3'),
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            bodies.add(body);
            if (bodies.length > 8) throw StateError('runaway retries');
            if (body.containsKey('thinking')) {
              return refuse('[1210][该模型始终思考，不支持关闭思考；请使用 low、high 或 max。][id]');
            }
            if (body.containsKey('output_config')) return refuse(leastMessage);
            return _stream(
              _reply([
                {'type': 'text', 'text': 'ok'},
              ]),
            );
          }),
        );
        addTearDown(provider.forgetLearned);
        await provider.chat(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        return (bodies, provider);
      }

      test('the least refused too, off sends nothing — once each', () async {
        for (final message in [
          // Zhipu's 5.3 answers every effort but low, high and max so.
          '[1210][该模型始终思考，不支持关闭思考；请使用 high 或 max。][id]',
          // Zhipu's own name for the field, translated.
          '[1210][reasoning_effort 参数值非法，可选值为：high、max][id]',
          // DashScope's words for a value it does not take.
          "Invalid value 'low' for output_config.effort. Supported values "
              'are: medium, high.',
          // A relay that does not know the field (Pydantic).
          '1 validation error for Request\noutput_config\n  Extra inputs are '
              "not permitted [type=extra_forbidden, input_value={'effort': "
              "'low'}, input_type=dict]",
          'Unknown parameter: output_config.effort',
        ]) {
          final (bodies, provider) = await leastRefused(message);
          expect(bodies, hasLength(3), reason: message);
          expect(bodies[0]['thinking'], {'type': 'disabled'});
          expect(bodies[1].containsKey('thinking'), isFalse);
          expect(bodies[1]['output_config'], {'effort': 'low'});
          expect(bodies[2].containsKey('thinking'), isFalse, reason: message);
          expect(
            bodies[2].containsKey('output_config'),
            isFalse,
            reason: message,
          );
          expect(provider.learned.thinkingOffTried, {
            LearnedBehaviour.dialectOff,
            LearnedBehaviour.leastEffortOff,
          }, reason: message);
          expect(provider.learned.rejectedFields, isEmpty, reason: message);
          provider.forgetLearned();
        }
      });

      test('the least is asked for off only: on is adaptive, alone', () async {
        final (_, provider) = await offRefused(
          '',
          '[1210][该模型始终思考，不支持关闭思考；请使用 low、high 或 max。][id]',
          endpoint: 'https://open.bigmodel.cn/api/anthropic',
          model: 'glm-5.3',
        );
        addTearDown(provider.forgetLearned);
        final on = await AnthropicProvider(
          _config(
            'https://open.bigmodel.cn/api/anthropic',
            model: 'glm-5.3',
            thinking: true,
          ),
        ).previewRequest(messages: const [UserMessage('u')], tools: const []);
        expect(on.body['thinking'], {'type': 'adaptive'});
        expect(on.body.containsKey('output_config'), isFalse);
      });

      test('a server that does not know thinking stops being told', () async {
        // Thinking off must not fail every request on a route whose server
        // refuses the field outright — and that is the field refused by
        // name, not a model that cannot stop: it says nothing about
        // whether the model reasons.
        final (bodies, provider) = await offRefused(
          'unknown-field.minimaxi.com',
          'thinking: Extra inputs are not permitted',
        );
        expect(bodies, hasLength(2));
        expect(bodies.last.containsKey('thinking'), isFalse);
        expect(provider.learned.thinkingOffTried, isEmpty);
        expect(provider.learned.rejectedFields, {
          'thinking',
          'thinking:adaptive',
          'thinking:enabled',
        });
        // On is not asked there either.
        final on = AnthropicProvider(
          _config(
            'https://unknown-field.minimaxi.com/anthropic',
            model: 'MiniMax-M3',
            thinking: true,
          ),
        );
        final preview = await on.previewRequest(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        expect(preview.body.containsKey('thinking'), isFalse);
      });

      test(
        'off refused under a translated name is the field, not the model',
        () async {
          // `disabled` translated by a relay and refused under the
          // upstream's name says nothing about whether the model can stop:
          // the field is given up, both ways, as an unknown field is.
          final (bodies, provider) = await offRefused(
            'translated-off.minimaxi.com',
            'Unrecognized request argument supplied: reasoning_effort',
          );
          expect(bodies, hasLength(2));
          expect(bodies.first['thinking'], {'type': 'disabled'});
          expect(bodies.last.containsKey('thinking'), isFalse);
          expect(provider.learned.thinkingOffTried, isEmpty);
          expect(provider.learned.rejectedFields, {
            'thinking',
            'thinking:adaptive',
            'thinking:enabled',
          });
        },
      );

      test(
        'a sampling value refused beside a word of reasoning is the value',
        () async {
          // Off goes out with the sampling values; the upstream refuses one
          // of them in words that mention reasoning in passing. That is the
          // value's refusal, not thinking's: the value is dropped, and off
          // is still said.
          for (final (i, message) in [
            "'top_p' is not supported with reasoning models.",
            'top_k is not supported when reasoning is enabled',
            'temperature is not supported when reasoning_effort is set',
          ].indexed) {
            final bodies = <Map<String, dynamic>>[];
            final provider = AnthropicProvider(
              _config(
                'https://sampling-refused-$i.minimaxi.com/anthropic',
                model: 'MiniMax-M3',
                temperature: 0.7,
                topP: 0.9,
                topK: 40,
              ),
              client: MockClient((request) async {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                bodies.add(body);
                if (bodies.length > 8) throw StateError('runaway retries');
                final field = RegExp(
                  'top_p|top_k|temperature',
                ).firstMatch(message)![0]!;
                return body.containsKey(field)
                    ? http.Response(
                        jsonEncode({
                          'type': 'error',
                          'error': {
                            'type': 'invalid_request_error',
                            'message': message,
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
            await provider.chat(
              messages: const [UserMessage('u')],
              tools: const [],
            );
            expect(bodies, hasLength(2), reason: message);
            expect(bodies.last['thinking'], {'type': 'disabled'});
            expect(provider.learned.thinkingOffTried, isEmpty);
            expect(
              provider.learned.rejectedFields,
              hasLength(1),
              reason: message,
            );
            expect(
              provider.learned.rejectedFields.single,
              isIn(['top_p', 'top_k', 'temperature']),
            );
          }
        },
      );

      test('a sentence is about the field it names first (#119 known issues '
          '2 and 3)', () async {
        // Off goes out with the sampling values. What is learned is what
        // the sentence is about — the field it names first — not which
        // reader ran first: a value named in passing is kept, and a value
        // refused beside the word thinking is the value, not thinking.
        Future<(List<Map<String, dynamic>>, AnthropicProvider)> refused(
          String host,
          String message,
        ) async {
          final bodies = <Map<String, dynamic>>[];
          final provider = AnthropicProvider(
            _config(
              'https://$host.minimaxi.com/anthropic',
              model: 'MiniMax-M3',
              temperature: 0.7,
              topP: 0.9,
              topK: 40,
            ),
            client: MockClient((request) async {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              bodies.add(body);
              if (bodies.length > 8) throw StateError('runaway retries');
              return bodies.length == 1
                  ? http.Response(
                      jsonEncode({
                        'type': 'error',
                        'error': {
                          'type': 'invalid_request_error',
                          'message': message,
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
          await provider.chat(
            messages: const [UserMessage('u')],
            tools: const [],
          );
          return (bodies, provider);
        }

        const every = {'thinking', 'thinking:adaptive', 'thinking:enabled'};
        var (bodies, provider) = await refused(
          'first-1',
          'reasoning_effort is not supported; use temperature instead',
        );
        expect(bodies, hasLength(2));
        expect(bodies.last.containsKey('thinking'), isFalse);
        expect(bodies.last['temperature'], 0.7);
        expect(provider.learned.rejectedFields, every);

        (bodies, provider) = await refused(
          'first-2',
          'reasoning is mandatory for this model; temperature is ignored',
        );
        expect(bodies, hasLength(2));
        expect(bodies.last.containsKey('thinking'), isFalse);
        expect(bodies.last['temperature'], 0.7);
        expect(provider.learned.rejectedFields, isEmpty);
        expect(provider.learned.thinkingOffTried, {
          LearnedBehaviour.dialectOff,
        });

        (bodies, provider) = await refused(
          'first-3',
          'Unsupported parameter: reasoning_effort. Supported parameters: '
              'temperature, top_p, top_k, max_tokens',
        );
        expect(bodies, hasLength(2));
        expect(bodies.last.containsKey('thinking'), isFalse);
        expect(bodies.last['top_k'], 40);
        expect(provider.learned.rejectedFields, every);

        for (final (i, (message, field)) in [
          ('temperature is not supported with thinking', 'temperature'),
          ('top_p is not supported in thinking mode', 'top_p'),
          (
            '`temperature` may only be set to 1 when thinking is enabled',
            'temperature',
          ),
        ].indexed) {
          (bodies, provider) = await refused('first-value-$i', message);
          expect(bodies, hasLength(2), reason: message);
          expect(bodies.last['thinking'], {'type': 'disabled'});
          expect(bodies.last.containsKey(field), isFalse, reason: message);
          expect(provider.learned.rejectedFields, {field}, reason: message);
          expect(provider.learned.thinkingOffTried, isEmpty);
        }
      });

      test(
        'off answered "mandatory" beside a translated name cannot stop',
        () async {
          final (bodies, provider) = await offRefused(
            'mandatory-translated.minimaxi.com',
            'reasoning is mandatory for this model',
          );
          expect(bodies, hasLength(2));
          expect(bodies.last.containsKey('thinking'), isFalse);
          expect(provider.learned.thinkingOffTried, {
            LearnedBehaviour.dialectOff,
          });
          expect(provider.learned.rejectedFields, isEmpty);
        },
      );

      test('a field refused in Pydantic words is the field, whatever it '
          'echoes', () async {
        // Pydantic's default message repeats the input it refused, value
        // and all; the words say the field is unknown, and they win.
        const echo =
            '1 validation error for MessagesRequest\nthinking\n  Extra inputs '
            "are not permitted [type=extra_forbidden, input_value={'type': "
            "'%s'}, input_type=dict]";
        final (offBodies, offProvider) = await offRefused(
          'echo-off.minimaxi.com',
          echo.replaceFirst('%s', 'disabled'),
        );
        expect(offBodies, hasLength(2));
        expect(offBodies.last.containsKey('thinking'), isFalse);
        expect(offProvider.learned.thinkingOffTried, isEmpty);
        expect(offProvider.learned.rejectedFields, contains('thinking'));

        final (onBodies, onProvider) = await refusing(
          'echo-on.minimaxi.com/anthropic',
          {'adaptive'},
          (type) => echo.replaceFirst('%s', type),
          model: 'MiniMax-M3',
        );
        expect(onBodies, hasLength(2));
        expect(onBodies.last.containsKey('thinking'), isFalse);
        expect(onProvider.learned.rejectedFields, {
          'thinking',
          'thinking:adaptive',
          'thinking:enabled',
        });
        final off = AnthropicProvider(
          _config(
            'https://echo-on.minimaxi.com/anthropic',
            model: 'MiniMax-M3',
          ),
        );
        final preview = await off.previewRequest(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        expect(preview.body.containsKey('thinking'), isFalse);
      });

      test('a full stop after thinking is not a sub-field', () async {
        // "thinking.Please" reads as thinking refused, not as a value the
        // server knows: the field is given up, and the model is not said
        // to always reason.
        final (bodies, provider) = await offRefused(
          'full-stop.minimaxi.com',
          'The model does not support thinking.Please remove the parameter',
        );
        expect(bodies, hasLength(2));
        expect(bodies.last.containsKey('thinking'), isFalse);
        expect(provider.learned.thinkingOffTried, isEmpty);
        expect(provider.learned.rejectedFields, contains('thinking'));
      });

      test(
        'a refusal naming thinking.type is of the value, either way',
        () async {
          // The sub-field named says the server knows the field: off records
          // the model cannot be told off, as on records only the form.
          final (bodies, provider) = await offRefused(
            'type-off.minimaxi.com',
            'invalid params: thinking.type is not supported',
          );
          expect(bodies, hasLength(2));
          expect(provider.learned.thinkingOffTried, {
            LearnedBehaviour.dialectOff,
          });
          expect(provider.learned.rejectedFields, isEmpty);
        },
      );

      test(
        'a server that knows the field and not disabled cannot stop',
        () async {
          // The value named back: the server takes `thinking`, only not off,
          // so the model reasons at its default and on is still asked.
          final (bodies, provider) = await offRefused(
            'no-disabled.minimaxi.com',
            "thinking.type: Input tag 'disabled' found using 'type' does not "
                "match any of the expected tags: 'adaptive'",
          );
          expect(bodies, hasLength(2));
          expect(bodies.last.containsKey('thinking'), isFalse);
          expect(provider.learned.thinkingOffTried, {
            LearnedBehaviour.dialectOff,
          });
          expect(provider.learned.rejectedFields, isEmpty);
        },
      );

      test(
        'a server that does not know thinking refuses on the same way',
        () async {
          final (bodies, provider) = await refusing(
            'unknown-field-on.minimaxi.com/anthropic',
            {'adaptive'},
            (_) => 'thinking: Extra inputs are not permitted',
            model: 'MiniMax-M3',
          );
          expect(bodies, hasLength(2));
          expect(bodies.last.containsKey('thinking'), isFalse);
          expect(provider.learned.thinkingOffTried, isEmpty);
          expect(provider.learned.rejectedFields, {
            'thinking',
            'thinking:adaptive',
            'thinking:enabled',
          });
          // Nor is off told `disabled` any more.
          final off = AnthropicProvider(
            _config(
              'https://unknown-field-on.minimaxi.com/anthropic',
              model: 'MiniMax-M3',
            ),
          );
          final preview = await off.previewRequest(
            messages: const [UserMessage('u')],
            tools: const [],
          );
          expect(preview.body.containsKey('thinking'), isFalse);
        },
      );

      test('an error about the history teaches nothing about off', () async {
        final (bodies, provider) = await offRefused(
          'history.minimaxi.com',
          'messages.1.content.0: thinking blocks cannot be sent while '
              'thinking is disabled',
        );
        expect(bodies, hasLength(1));
        expect(provider.learned.thinkingOffTried, isEmpty);
      });

      test('a refused adaptive is not swapped for a budget', () async {
        // A host of its own: what this route learns must not reach the
        // bodies the tests above read.
        final (bodies, provider) = await refusing(
          'refused.minimaxi.com/anthropic',
          {'adaptive'},
          (type) => "thinking.type: unsupported value '$type'",
          model: 'MiniMax-M3',
        );
        expect(
          bodies.map((b) => (b['thinking'] as Map?)?['type']),
          everyElement(isNot('enabled')),
        );
        // Its one form refused: thinking is given up, not tried another way.
        // The form is what was named, so the server knows the field, and
        // off still says `disabled`.
        expect(provider.learned.rejectedFields, {'thinking:adaptive'});
        final off = AnthropicProvider(
          _config(
            'https://refused.minimaxi.com/anthropic',
            model: 'MiniMax-M3',
          ),
        );
        final preview = await off.previewRequest(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        expect(preview.body['thinking'], {'type': 'disabled'});
      });

      test('a form named without refusing thinking is thrown', () async {
        // With no other form to try, only a refusal of thinking itself may
        // drop it; anything else would switch reasoning off unasked.
        final bodies = <Map<String, dynamic>>[];
        final provider = AnthropicProvider(
          _config(
            'https://tag.minimaxi.com/anthropic',
            model: 'MiniMax-M3',
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
                      "thinking.type: Input tag 'adaptive' found using "
                      "'type' does not match any of the expected tags",
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

      test('adaptive on record as refused leaves no form to ask', () async {
        final key = LearnedStore.routeKey(
          protocol: AiProviderType.anthropic.id,
          base: 'https://seeded.minimaxi.com/anthropic/v1',
          model: 'MiniMax-M3',
          apiKey: 'sk-ant-secret',
        );
        LearnedStore.instance.update(
          key,
          (b) => b.copyWith(rejectedFields: {'thinking:adaptive'}),
        );
        late Map<String, dynamic> body;
        final provider = AnthropicProvider(
          _config(
            'https://seeded.minimaxi.com/anthropic',
            model: 'MiniMax-M3',
            thinking: true,
          ),
          client: MockClient((request) async {
            body = jsonDecode(request.body);
            return _stream(
              _reply([
                {'type': 'text', 'text': 'ok'},
              ]),
            );
          }),
        );
        expect(provider.learned.rejectedFields, {'thinking:adaptive'});
        await provider.chat(
          messages: const [UserMessage('u')],
          tools: const [],
        );
        expect(body.containsKey('thinking'), isFalse);
      });
    });

    test('both forms refused by name give thinking up', () async {
      const both = {'adaptive', 'enabled'};
      final (bodies, provider) = await refusing(
        'both-forms.example',
        both,
        (type) => "thinking.type: '$type' is not supported for this model",
      );
      expect(bodies.map((b) => (b['thinking'] as Map?)?['type']), [
        'adaptive',
        'enabled',
        null,
      ]);
      expect(
        provider.learned.rejectedFields,
        containsAll(['thinking:adaptive', 'thinking:enabled', 'thinking']),
      );
    });

    /// The bodies a route with an old bare `thinking` record sends for
    /// [model]: the first request answered, the rest refused as an older
    /// Claude refuses adaptive.
    Future<List<Map<String, dynamic>>> legacy(String host, String model) async {
      final bodies = <Map<String, dynamic>>[];
      final provider = AnthropicProvider(
        _config('https://$host', model: model, thinking: true),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          return (body['thinking'] as Map?)?['type'] == 'adaptive' &&
                  !model.contains('4-6')
              ? http.Response(
                  jsonEncode({
                    'type': 'error',
                    'error': {
                      'type': 'invalid_request_error',
                      'message':
                          "thinking.type: Input tag 'adaptive' found using "
                          "'type' does not match any of the expected tags: "
                          "'disabled', 'enabled'",
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
      LearnedStore.instance.update(
        LearnedStore.routeKey(
          protocol: AiProviderType.anthropic.id,
          base: 'https://$host/v1',
          model: model,
          apiKey: 'sk-ant-secret',
        ),
        (b) => b.copyWith(rejectedFields: {'thinking'}),
      );
      expect(provider.learned.rejectedFields, {'thinking'});
      await provider.chat(messages: const [UserMessage('u')], tools: const []);
      return bodies;
    }

    test('an old bare `thinking` record is not the end of thinking', () async {
      final bodies = await legacy('legacy-thinking.example', 'claude-opus-4-6');
      expect(bodies.single['thinking'], {'type': 'adaptive'});
    });

    test('an old bare `thinking` record still ends it for a budget', () async {
      // Its own form, `enabled`, was refused as a feature; asking adaptive
      // of it would fail every request, since only a refusal of thinking
      // itself may give thinking up.
      final bodies = await legacy('legacy-budget.example', 'claude-3-5-haiku');
      expect(bodies.single.containsKey('thinking'), isFalse);
    });

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
      // Another protocol's name for the field is read only in the words of
      // a refusal: `reasoning` is an ordinary word, and a name mentioned
      // with nothing refused is about something else.
      (
        'saying reasoning in prose',
        'deepseek-r1-distill-qwen-14b',
        'the model was reasoning about the request and found it invalid',
      ),
      (
        'mentioning a translated name with nothing refused',
        'deepseek-r1-distill-qwen-14b',
        'reasoning_effort was set to medium; the upstream timed out',
      ),
      (
        'about reasoning_content, which is not the field',
        'deepseek-r1-distill-qwen-14b',
        "'reasoning_content' must be a string when present",
      ),
      (
        'refusing reasoning_content in the history',
        'deepseek-r1-distill-qwen-14b',
        'reasoning_content is not supported in input messages',
      ),
      (
        'listing a translated name among the parameters supported',
        'deepseek-r1-distill-qwen-14b',
        'Unsupported parameter: top_k. Supported parameters: '
            'reasoning_effort, max_tokens',
      ),
      (
        'echoing the translated body beside another refusal',
        'deepseek-r1-distill-qwen-14b',
        "Value error, 'auto' tool choice is not supported "
            "[type=value_error, input_value={'model': 'x', "
            "'messages': [{'role': 'user'}], 'reasoning_effort': 'high', "
            "'tool_choice': 'auto'}, input_type=dict]",
      ),
      // A family that never reasons sends no `thinking`, so a translated
      // name refused is about something else the relay sent.
      (
        'refusing a translated name when no thinking was sent',
        'qwen3-30b-a3b-instruct-2507',
        'Unrecognized request argument supplied: reasoning_effort',
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

    group('without message_stop', () {
      Future<ChatResult> read(String host, String body) => AnthropicProvider(
        _config('https://$host'),
        client: MockClient(
          (_) async => http.Response(
            body,
            200,
            headers: const {'content-type': 'text/event-stream'},
          ),
        ),
      ).chat(messages: const [UserMessage('u')], tools: const []);

      test('closed blocks are an answer', () async {
        // A relay that drops the last event.
        final result = await read(
          'no-stop.example',
          _sse(
            _reply([
              {'type': 'text', 'text': 'whole'},
            ], terminated: false),
          ),
        );
        expect(result.text, 'whole');
      });

      test('closed thinking alone is not', () async {
        await expectLater(
          read(
            'thinking-only.example',
            _sse(
              _reply([
                {'type': 'thinking', 'thinking': 'hm', 'signature': 's'},
              ], terminated: false),
            ),
          ),
          throwsA(isA<AiNetworkException>()),
        );
      });

      test('text that arrived only in deltas counts', () async {
        final result = await read(
          'delta-text.example',
          _sse([
            {
              'type': 'message_start',
              'message': {'usage': <String, Object?>{}},
            },
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'text', 'text': ''},
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'whole'},
            },
            {'type': 'content_block_stop', 'index': 0},
          ]),
        );
        expect(result.text, 'whole');
        expect(result.finishReason, isNull);
      });

      test('is marked in the request log', () async {
        final dir = await Directory.systemTemp.createTemp('messages_log');
        addTearDown(() async {
          ApiLog.instance
            ..enabled = false
            ..directory = null;
          await dir.delete(recursive: true);
        });
        ApiLog.instance
          ..directory = dir
          ..enabled = true;

        final text = [
          {'type': 'text', 'text': 'whole'},
        ];
        await read(
          'logged-no-stop.example',
          _sse(_reply(text, terminated: false)),
        );
        await read('logged-stop.example', _sse(_reply(text)));
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

      test('a block cut mid-way is not', () async {
        final events = [
          {
            'type': 'message_start',
            'message': {'usage': <String, Object?>{}},
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'half'},
          },
        ];
        await expectLater(
          read('cutoff.example', _sse(events)),
          throwsA(isA<AiNetworkException>()),
        );
      });

      test('a tool input cut mid-way is not', () async {
        final events = [
          {
            'type': 'message_start',
            'message': {'usage': <String, Object?>{}},
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 't',
              'name': 'f',
              'input': <String, Object?>{},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'input_json_delta', 'partial_json': '{"a": '},
          },
        ];
        await expectLater(
          read('cut-tool.example', _sse(events)),
          throwsA(isA<AiNetworkException>()),
        );
      });
    });

    test('a skipped event fails even a finished stream', () async {
      // It may have been a text or tool-input delta.
      final body = _sse(
        _reply([
          {'type': 'text', 'text': 'whole'},
        ]),
      );
      await expectLater(
        AnthropicProvider(
          _config('https://skipped.example'),
          client: MockClient(
            (_) async => http.Response(
              'data: {"type": "content_block_delta", \n\n$body',
              200,
              headers: const {'content-type': 'text/event-stream'},
            ),
          ),
        ).chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('an empty data line is no event', () async {
      final body = _sse(
        _reply([
          {'type': 'text', 'text': 'whole'},
        ]),
      );
      final result = await AnthropicProvider(
        _config('https://empty-data.example'),
        client: MockClient(
          (_) async => http.Response(
            'data:\n\n$body',
            200,
            headers: const {'content-type': 'text/event-stream'},
          ),
        ),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      expect(result.text, 'whole');
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

  test('a timed-out generation is sent once, as a timeout', () async {
    for (final (name, answer) in [
      (
        'slow',
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _stream(
            _reply([
              {'type': 'text', 'text': 'too late'},
            ]),
          );
        },
      ),
      ('gateway', () async => http.Response('upstream timed out', 504)),
    ]) {
      var calls = 0;
      final client = RecordingClient(
        MockClient((_) {
          calls++;
          return answer();
        }),
      );
      final provider = AnthropicProvider(
        _config('https://$name.example'),
        firstEventTimeout: const Duration(milliseconds: 30),
        client: client,
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiTimeoutException>()),
        reason: name,
      );
      expect(calls, 1, reason: name);
      if (name == 'slow') await expectLater(abortOf(client.last), completes);
    }
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
      MessagesRefusal.refusesThinking(
        'http 400: thinking: extra inputs are not permitted',
      ),
      isTrue,
    );
    expect(
      MessagesRefusal.refusesThinking(
        'http 400: this model does not support thinking',
      ),
      isTrue,
    );
    expect(
      MessagesRefusal.refusesThinking(
        'http 400: max_tokens must be greater than thinking.budget_tokens',
      ),
      isFalse,
    );
  });

  test('a 400 about thinking is read the same way, whichever way was asked', () {
    ThinkingRefusal read(String detail, {String sent = 'adaptive'}) =>
        MessagesRefusal.readThinkingRefusal(
          detail.toLowerCase(),
          sentType: sent,
        );
    const echo =
        "[type=extra_forbidden, input_value={'type': '%s'}, input_type=dict]";

    // The model cannot stop: said without naming the field, and only in
    // answer to off — asked on, the same words read as what is beside them.
    expect(
      read('该模型始终思考，不支持关闭思考', sent: 'disabled'),
      ThinkingRefusal.cannotStop,
    );
    expect(
      read('this model always thinks', sent: 'disabled'),
      ThinkingRefusal.cannotStop,
    );
    // "mandatory" counts beside another protocol's name for the field —
    // a relay's translation — and, like the words above, answers off alone.
    expect(
      read('reasoning is mandatory for this model', sent: 'disabled'),
      ThinkingRefusal.cannotStop,
    );
    expect(
      read('reasoning_effort: a value is mandatory', sent: 'disabled'),
      ThinkingRefusal.cannotStop,
    );
    expect(
      read('messages is mandatory', sent: 'disabled'),
      ThinkingRefusal.unrelated,
    );
    // DashScope's Messages face, in its own name for the field
    // (【实测 2026-09-28】); the same words about any other parameter are not
    // the model.
    expect(
      read(
        'the value of the enable_thinking parameter is restricted to true.',
        sent: 'disabled',
      ),
      ThinkingRefusal.cannotStop,
    );
    expect(
      read(
        'the value of the frobnicate parameter is restricted to true.',
        sent: 'disabled',
      ),
      ThinkingRefusal.unrelated,
    );
    expect(
      read('reasoning is mandatory for this model'),
      ThinkingRefusal.unrelated,
    );
    expect(
      read('thinking.type 参数非法：该模型始终思考，不支持关闭思考', sent: 'adaptive'),
      ThinkingRefusal.valueNamed,
    );
    expect(read('this model always thinks'), ThinkingRefusal.unrelated);

    // The field itself unknown, in each server's words — whatever value
    // Pydantic echoes beside them.
    for (final detail in [
      'thinking: Extra inputs are not permitted',
      'thinking\n  Extra inputs are not permitted ${echo.replaceFirst('%s', 'disabled')}',
      'thinking\n  Extra inputs are not permitted ${echo.replaceFirst('%s', 'adaptive')}',
      'thinking: unknown field',
      'Unknown parameter: thinking',
      'Unrecognized request argument supplied: thinking',
    ]) {
      for (final sent in ['adaptive', 'enabled', 'disabled']) {
        expect(
          read(detail, sent: sent),
          ThinkingRefusal.fieldUnknown,
          reason: '$detail / $sent',
        );
      }
    }

    // Another protocol's name for the field, refused — a relay translated
    // `thinking` into its upstream's field — is the field unknown, in the
    // words of a refusal, of an unknown field, of a mandatory one, or with
    // the name quoted; whichever way was asked, since what the relay sent
    // for it is not ours to read.
    for (final detail in [
      'unrecognized request argument supplied: reasoning_effort',
      'reasoning_effort\n  extra inputs are not permitted '
          "[type=extra_forbidden, input_value='medium', input_type=str]",
      "unknown parameter: 'reasoning_effort'.",
      "unsupported parameter: 'reasoning_effort' is not supported with "
          'this model.',
      'unrecognized request argument supplied: chat_template_kwargs',
      'invalid json payload received. unknown name "thinkingconfig" at '
          "'generation_config': cannot find field.",
      "'reasoning' is not a valid parameter",
      "invalid value for 'reasoning_effort': expected one of low, medium",
      "invalid value for 'reasoning.effort': expected one of low, medium",
      'invalid json payload received. unknown name "thinking_config" at '
          "'generation_config': cannot find field.",
      'argument not supported on this model: reasoningeffort',
      'unrecognized request argument supplied: enable_thinking',
    ]) {
      for (final sent in ['adaptive', 'enabled', 'disabled']) {
        expect(
          read(detail, sent: sent),
          ThinkingRefusal.fieldUnknown,
          reason: '$detail / $sent',
        );
      }
    }
    // A translated name that says `thinking` is read as the words say —
    // the feature refused — which records the same.
    expect(
      read("unsupported parameter: 'enable_thinking' is not supported"),
      ThinkingRefusal.featureRefused,
    );

    // A sub-field named says the server knows the field: the value, even
    // in unknown-field words.
    expect(
      read(
        "thinking.type\n  Input should be 'adaptive' or 'disabled' "
        "[type=literal_error, input_value='enabled']\nthinking.budget_tokens\n"
        '  Extra inputs are not permitted [type=extra_forbidden]',
        sent: 'enabled',
      ),
      ThinkingRefusal.valueRefused,
    );
    expect(
      read("thinking.type: unsupported value 'adaptive'"),
      ThinkingRefusal.valueRefused,
    );
    // Any sub-field, not only the type.
    expect(
      read(
        'thinking.budget_tokens\n  Extra inputs are not permitted '
        '[type=extra_forbidden, input_value=1024]',
        sent: 'enabled',
      ),
      ThinkingRefusal.valueRefused,
    );
    expect(
      read('invalid params: thinking.type is not supported', sent: 'disabled'),
      ThinkingRefusal.valueRefused,
    );
    expect(
      read(
        "thinking.type: Input tag 'adaptive' found using 'type' does not "
        "match any of the expected tags: 'disabled', 'enabled'",
      ),
      ThinkingRefusal.valueNamed,
    );
    expect(
      read('thinking is disabled for this account', sent: 'disabled'),
      ThinkingRefusal.valueNamed,
    );

    // Thinking itself, naming no field or value — a full stop, a docs URL
    // or a relay alias after the word is not a sub-field.
    expect(
      read('this model does not support thinking'),
      ThinkingRefusal.featureRefused,
    );
    for (final detail in [
      'The model does not support thinking.Please remove the parameter',
      'thinking is not supported by this model, see '
          'https://docs.example.com/guide/thinking.html',
      'thinking is not supported on -thinking.v2',
    ]) {
      for (final sent in ['adaptive', 'disabled']) {
        expect(
          read(detail, sent: sent),
          ThinkingRefusal.featureRefused,
          reason: '$detail / $sent',
        );
      }
    }
    expect(
      read('`thinking` is not supported for this model', sent: 'disabled'),
      ThinkingRefusal.featureRefused,
    );

    // Not about the request for thinking.
    for (final detail in [
      'max_tokens must be greater than thinking.budget_tokens',
      // A budget error that names the form is still about the numbers.
      'thinking.type enabled requires max_tokens greater than '
          'thinking.budget_tokens',
      // So is a budget out of range, with nothing refused beside it.
      'thinking.budget_tokens\n  Input should be less than or equal to '
          '32000 [type=less_than_equal, input_value=65536, input_type=int]',
      'messages.1.content.0: thinking blocks cannot be sent while thinking '
          'is disabled',
      'messages.3.content.0: Invalid `signature` in `thinking` block',
      // A relay's upstream alias, left after the model id is taken out.
      'unrecognized model: -thinking',
      'model -thinking is unavailable',
      'top_k: Extra inputs are not permitted',
      // Another protocol's name mentioned with nothing refused, or an
      // ordinary word that is a prefix of one.
      'the model was reasoning about the request and found it invalid',
      'reasoning_effort was set to medium; the upstream timed out',
      "'reasoning_content' must be a string when present",
      'reasoning_content is empty',
      // Refused in the history, not a name for the field.
      'reasoning_content is not supported in input messages',
      // Named in another sentence than the refusal, or in the input
      // Pydantic echoes: the relay's whole translated body.
      'unsupported parameter: top_k. supported parameters: '
          'reasoning_effort, max_tokens',
      "value error, 'auto' tool choice is not supported [type=value_error, "
          "input_value={'model': 'x', 'messages': [{'role': 'user'}], "
          "'reasoning_effort': 'high'}, input_type=dict]",
      "value error, 'auto' tool choice is not supported [type=value_error, "
          "input_value={'stop': ']', 'reasoning_effort': 'high'}, "
          'input_type=dict]',
    ]) {
      for (final sent in ['adaptive', 'enabled', 'disabled']) {
        expect(
          read(detail, sent: sent),
          ThinkingRefusal.unrelated,
          reason: '$detail / $sent',
        );
      }
    }

    // Unknown-field words are a kind of refusal: one set within the other.
    for (final detail in [
      'thinking: extra inputs are not permitted',
      'thinking: unknown field',
      'unrecognized request argument supplied: thinking',
      'thinking [type=extra_forbidden]',
    ]) {
      expect(MessagesRefusal.refusesThinkingField(detail), isTrue);
      expect(MessagesRefusal.refusesThinking(detail), isTrue, reason: detail);
    }
  });

  test('a tool input streamed as two objects becomes one', () async {
    final result = await AnthropicProvider(
      _config('https://concatenated-input.example'),
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
              'type': 'tool_use',
              'id': 't',
              'name': 'f',
              'input': <String, Object?>{},
            },
          },
          for (final piece in ['{}', '{"title": "Dune"}'])
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'input_json_delta', 'partial_json': piece},
            },
          {'type': 'content_block_stop', 'index': 0},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
          },
          {'type': 'message_stop'},
        ]),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);
    expect(result.toolCalls.single.decodedArguments, {'title': 'Dune'});
    expect((result.raw!.parts.single as Map)['input'], {'title': 'Dune'});
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

  group('whether the reply reasoned', () {
    Future<bool> reasoned(List<Map<String, Object?>> blocks) async {
      final result = await AnthropicProvider(
        _config('https://reasoned.example'),
        client: MockClient((_) async => _stream(_reply(blocks))),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      return result.reasoned;
    }

    test(
      'a thinking block with text, or a redacted one, is reasoning',
      () async {
        expect(
          await reasoned([
            {'type': 'thinking', 'thinking': 'hm', 'signature': 's'},
            {'type': 'text', 'text': 'ok'},
          ]),
          isTrue,
        );
        expect(
          await reasoned([
            {'type': 'redacted_thinking', 'data': 'x'},
            {'type': 'text', 'text': 'ok'},
          ]),
          isTrue,
        );
      },
    );

    test('a block empty of text with a signature is reasoning too', () async {
      // Claude 5 under the default `display` (omitted): no text, a
      // signature (KB 03 §3, 2026-09-26).
      expect(
        await reasoned([
          {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
          {'type': 'text', 'text': 'ok'},
        ]),
        isTrue,
      );
    });

    test('a block with neither text nor a signature is not', () async {
      // DashScope's kimi-k2.6 sends one when reasoning is not asked for or
      // is turned off (2026-09-28); read as reasoning, the connection test
      // would say thinking did not turn off.
      expect(
        await reasoned([
          {'type': 'thinking', 'thinking': '', 'signature': ''},
          {'type': 'text', 'text': 'ok'},
        ]),
        isFalse,
      );
      expect(
        await reasoned([
          {'type': 'thinking', 'thinking': ''},
          {'type': 'text', 'text': 'ok'},
        ]),
        isFalse,
      );
      expect(
        await reasoned([
          {'type': 'text', 'text': 'ok'},
        ]),
        isFalse,
      );
    });
  });
}
