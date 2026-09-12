import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/connection_check.dart';
import 'package:jellyfin_media_management_tool/services/ai/google_genai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';

import '../../helpers/ai.dart';

const _tool = ToolDefinition(
  name: 'submit',
  description: 'Submits a decision.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
    },
    'required': ['title'],
  },
);

AiConfig _openAi(String host) => AiConfig(
  provider: AiProviderType.openAi,
  endpoint: 'http://$host:1234/v1',
  apiKey: '',
  model: 'local-model',
);

String _event(Map<String, Object?> event) => 'data: ${jsonEncode(event)}\n\n';

Map<String, Object?> _delta(Map<String, Object?> delta, {String? finish}) => {
  'choices': [
    {'delta': delta, 'finish_reason': finish},
  ],
};

void main() {
  group('OpenAI-compatible tool calls', () {
    test('streamed fragments are assembled by index', () async {
      late Map<String, dynamic> sent;
      final provider = OpenAiProvider(
        _openAi('fragments'),
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            [
              _event(_delta({'reasoning_content': 'Which title is it?'})),
              _event(
                _delta({
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_a',
                      'function': {'name': 'submit', 'arguments': '{"ti'},
                    },
                  ],
                }),
              ),
              _event(
                _delta({
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': 'tle": "Dune'},
                    },
                  ],
                }),
              ),
              _event(
                _delta({
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '"}'},
                    },
                  ],
                }, finish: 'tool_calls'),
              ),
              'data: [DONE]\n\n',
            ].join(),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      final result = await provider.chat(
        messages: const [SystemMessage('s'), UserMessage('u')],
        tools: const [_tool],
      );

      expect(sent.containsKey('response_format'), isFalse);
      expect((sent['tools'] as List).single['function']['name'], 'submit');
      final call = result.toolCalls.single;
      expect(call.id, 'call_a');
      expect(call.name, 'submit');
      expect(call.decodedArguments, {'title': 'Dune'});
      expect(result.finishReason, 'tool_calls');
      expect(result.reasoning, (
        field: 'reasoning_content',
        text: 'Which title is it?',
      ));
    });

    test('an id and name repeated in every fragment are not doubled', () async {
      final provider = OpenAiProvider(
        _openAi('repeats'),
        client: MockClient(
          (_) async => http.Response(
            [
              for (final piece in ['{"title":', ' "Dune"}'])
                _event(
                  _delta({
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_b',
                        'function': {'name': 'submit', 'arguments': piece},
                      },
                    ],
                  }),
                ),
              'data: [DONE]\n\n',
            ].join(),
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );

      final call = (await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [_tool],
      )).toolCalls.single;

      expect(call.id, 'call_b');
      expect(call.name, 'submit');
      expect(call.decodedArguments, {'title': 'Dune'});
    });

    test('a plain JSON reply with decoded arguments is re-encoded', () async {
      final provider = OpenAiProvider(
        _openAi('plain-tools'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': null,
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'submit',
                          'arguments': {'title': 'Dune'},
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
            200,
          ),
        ),
      );

      final call = (await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [_tool],
      )).toolCalls.single;

      expect(call.id, 'call_0');
      expect(call.decodedArguments, {'title': 'Dune'});
    });

    test(
      'the history goes back with calls, results and their reasoning',
      () async {
        late Map<String, dynamic> sent;
        final provider = OpenAiProvider(
          _openAi('history'),
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'done'},
                    'finish_reason': 'stop',
                  },
                ],
              }),
              200,
            );
          }),
        );

        await provider.chat(
          messages: const [
            SystemMessage('s'),
            UserMessage('u'),
            AssistantMessage(
              toolCalls: [
                ToolCall(id: 'c1', name: 'submit', arguments: '{"title":"x"}'),
              ],
              reasoning: (field: 'reasoning_content', text: 'thinking'),
            ),
            ToolResultMessage(toolCallId: 'c1', name: 'submit', content: 'ok'),
            AssistantMessage(content: 'plain turn'),
          ],
          tools: const [_tool],
        );

        final wire = (sent['messages'] as List).cast<Map<String, dynamic>>();
        expect(wire[2]['content'], isNull);
        expect(
          wire[2]['tool_calls'][0]['function']['arguments'],
          '{"title":"x"}',
        );
        expect(wire[2]['reasoning_content'], 'thinking');
        expect(wire[3], {
          'role': 'tool',
          'tool_call_id': 'c1',
          'content': 'ok',
        });
        expect(wire[4].containsKey('reasoning_content'), isFalse);
        expect(wire[4]['content'], 'plain turn');
      },
    );
  });

  group('Gemini tool calls', () {
    const config = AiConfig(
      provider: AiProviderType.googleGenAi,
      endpoint: 'https://gemini.test',
      apiKey: 'key',
      model: 'gemini-2.0-flash',
    );

    test('function calls are read, and their parts return verbatim', () async {
      final bodies = <Map<String, dynamic>>[];
      final parts = [
        {
          'functionCall': {
            'name': 'submit',
            'args': {'title': 'Dune'},
          },
          'thoughtSignature': 'opaque-signature',
        },
      ];
      final provider = GoogleGenAiProvider(
        config,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {'role': 'model', 'parts': parts},
                  'finishReason': 'STOP',
                },
              ],
            }),
            200,
          );
        }),
      );

      final first = await provider.chat(
        messages: const [SystemMessage('s'), UserMessage('u')],
        tools: const [_tool],
      );
      expect(first.toolCalls.single.decodedArguments, {'title': 'Dune'});
      expect(
        bodies.first['tools'][0]['functionDeclarations'][0]['name'],
        'submit',
      );
      expect(
        bodies.first['generationConfig'].containsKey('responseMimeType'),
        isFalse,
      );

      await provider.chat(
        messages: [
          const SystemMessage('s'),
          const UserMessage('u'),
          first.toMessage(),
          ToolResultMessage(
            toolCallId: first.toolCalls.single.id,
            name: 'submit',
            content: 'ok',
          ),
        ],
        tools: const [_tool],
      );
      final contents = (bodies.last['contents'] as List)
          .cast<Map<String, dynamic>>();
      expect(contents[1]['role'], 'model');
      expect(contents[1]['parts'][0]['thoughtSignature'], 'opaque-signature');
      expect(contents[2]['parts'][0]['functionResponse']['name'], 'submit');
    });

    test('one round of results becomes one user turn', () {
      final contents = GoogleGenAiProvider.contents(const [
        UserMessage('u'),
        AssistantMessage(
          toolCalls: [
            ToolCall(id: 'a', name: 'submit', arguments: '{}'),
            ToolCall(id: 'b', name: 'submit', arguments: '{}'),
          ],
        ),
        ToolResultMessage(toolCallId: 'a', name: 'submit', content: '1'),
        ToolResultMessage(toolCallId: 'b', name: 'submit', content: '2'),
      ]);

      expect(contents, hasLength(3));
      expect(contents[2]['parts'], hasLength(2));
    });
  });

  group('tool support check', () {
    test('a model that calls the probe tool supports tools', () async {
      final provider = ScriptedChatProvider([
        (_) => toolTurn([
          ('report_greeting', {'greeting': 'hi'}),
        ]),
      ]);

      final probe = await AiConnectionCheck.probeTools(provider);
      expect(probe.outcome, ToolProbe.supported);
    });

    test(
      'a model that answers in prose is asked once more, then fails',
      () async {
        final provider = ScriptedChatProvider([(_) => textTurn('Hello!')]);

        final probe = await AiConnectionCheck.probeTools(provider);
        expect(probe.outcome, ToolProbe.unsupported);
        expect(provider.calls, 2);
      },
    );

    test('a second chance is enough', () async {
      final provider = ScriptedChatProvider([
        (_) => textTurn('Hello!'),
        (_) => toolTurn([
          ('report_greeting', {'greeting': 'hi'}),
        ]),
      ]);

      final probe = await AiConnectionCheck.probeTools(provider);
      expect(probe.outcome, ToolProbe.supported);
    });

    test('a transport failure is inconclusive, never a verdict', () async {
      var calls = 0;
      final provider = ThrowingChatProvider(() {
        calls++;
        return const AiNetworkException('Network error: Connection refused');
      });

      final probe = await AiConnectionCheck.probeTools(provider);

      // A dropped connection says nothing about the model. Recording its
      // `false` on the profile disables Organize and the scrape panel's LLM
      // buttons until a human thinks to re-run the connection test.
      expect(probe.outcome, ToolProbe.inconclusive);
      expect(probe.error, contains('Connection refused'));
      expect(calls, 2, reason: 'a blip gets the second attempt too');
    });

    test('a server that refuses the tools field settles it', () async {
      final provider = ThrowingChatProvider(
        () => const AiException("HTTP 400: Unsupported parameter: 'tools'"),
      );

      final probe = await AiConnectionCheck.probeTools(provider);

      // The endpoint answered. That is a fact about this model.
      expect(probe.outcome, ToolProbe.unsupported);
    });

    test(
      'ensureTools reports the network failure, and records nothing',
      () async {
        final service = AiService();
        final recorded = <bool>[];
        service.onToolSupport = (_, supported) => recorded.add(supported);

        await expectLater(
          service.ensureTools(
            AiConfig(
              provider: AiProviderType.openAi,
              endpoint: 'http://127.0.0.1:1/v1',
              apiKey: '',
              model: 'never-answers',
            ),
          ),
          throwsA(isA<AiNetworkException>()),
        );
        expect(recorded, isEmpty);
      },
    );

    test(
      'a result only counts for the endpoint and model it was measured on',
      () {
        final tested = _openAi('support').withToolSupport(true);
        expect(tested.supportsTools, isTrue);

        final otherModel = AiConfig.fromJson({
          ...tested.toJson(),
          'model': 'another-model',
        });
        expect(otherModel.supportsTools, isNull);
        expect(AiConfig.fromJson(tested.toJson()).supportsTools, isTrue);
      },
    );
  });
}
