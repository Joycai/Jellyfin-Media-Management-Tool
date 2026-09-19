import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/openai_responses_provider.dart';

AiConfig _config(String host, {String model = 'gpt-5.4'}) => AiConfig(
  provider: AiProviderType.openAiResponses,
  endpoint: 'https://$host',
  apiKey: 'sk-resp',
  model: model,
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

  test('a stream with no terminal event is not an answer', () async {
    await expectLater(
      OpenAiResponsesProvider(
        _config('no-terminal.example'),
        client: MockClient(
          (_) async => _stream([
            _done(0, {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'half'},
              ],
            }),
          ]),
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
