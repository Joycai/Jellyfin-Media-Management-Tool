import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_http.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';
import 'package:jellyfin_media_management_tool/services/ai/connection_check.dart';
import 'package:jellyfin_media_management_tool/services/ai/google_genai_provider.dart';

// Each test uses its own host: the provider remembers per endpoint + model
// which way of asking for no reasoning this server took.
AiConfig _config(
  String host, {
  bool thinking = false,
  String model = 'gemini-2.5-flash',
}) => AiConfig(
  provider: AiProviderType.googleGenAi,
  endpoint: 'https://$host',
  apiKey: 'secret-key-value',
  model: model,
  thinkingEnabled: thinking,
);

http.Response _ok(
  Map<String, Object?> body, {
  Map<String, Object?>? usage,
  String finishReason = 'STOP',
}) => http.Response(
  jsonEncode({
    'candidates': [
      {'content': body, 'finishReason': finishReason},
    ],
    'usageMetadata': ?usage,
  }),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _text(
  String text, {
  Map<String, Object?>? usage,
  String finishReason = 'STOP',
}) => _ok(
  {
    'parts': [
      {'text': text},
    ],
  },
  usage: usage,
  finishReason: finishReason,
);

Map<String, dynamic> _body(http.BaseRequest request) =>
    jsonDecode((request as http.Request).body) as Map<String, dynamic>;

Map<String, dynamic> _generationConfig(http.BaseRequest request) =>
    _body(request)['generationConfig'] as Map<String, dynamic>;

void main() {
  group('thinking control', () {
    test('thinking off asks for a zero budget', () async {
      late http.BaseRequest seen;
      await GoogleGenAiProvider(
        _config('budget'),
        client: MockClient((request) async {
          seen = request;
          return _text('hi');
        }),
      ).complete(systemPrompt: 's', userPrompt: 'u');

      expect(_generationConfig(seen)['thinkingConfig'], {'thinkingBudget': 0});
    });

    test('thinking on sends no thinkingConfig, leaving the default', () async {
      late http.BaseRequest seen;
      await GoogleGenAiProvider(
        _config('on', thinking: true),
        client: MockClient((request) async {
          seen = request;
          return _text('hi');
        }),
      ).complete(systemPrompt: 's', userPrompt: 'u');

      expect(_generationConfig(seen).containsKey('thinkingConfig'), isFalse);
    });

    test('a model that refuses the budget is asked with a level', () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = GoogleGenAiProvider(
        _config('refuses'),
        client: MockClient((request) async {
          bodies.add(_body(request));
          final config =
              bodies.last['generationConfig'] as Map<String, dynamic>;
          final thinking = config['thinkingConfig'] as Map<String, Object?>?;
          if (thinking != null && thinking.containsKey('thinkingBudget')) {
            return http.Response(
              jsonEncode({
                'error': {
                  'message':
                      'Budget 0 is invalid; thinking_budget must be at '
                      'least 128 for this model.',
                },
              }),
              400,
            );
          }
          return _text('hi');
        }),
      );

      await provider.complete(systemPrompt: 's', userPrompt: 'u');

      expect(bodies, hasLength(2));
      expect((bodies.last['generationConfig'] as Map)['thinkingConfig'], {
        'thinkingLevel': 'low',
      });
    });

    test(
      'a reply that still reasoned moves the next request on, and says so',
      () async {
        final provider = GoogleGenAiProvider(
          _config('ignored'),
          client: MockClient(
            (request) async => _text(
              'hi',
              usage: const {
                'promptTokenCount': 10,
                'candidatesTokenCount': 2,
                'thoughtsTokenCount': 400,
              },
            ),
          ),
        );

        final first = await provider.complete(
          systemPrompt: 's',
          userPrompt: 'u',
        );
        expect(first.reasoned, isTrue);
        // There is one more way to try, so the caller can retry to find it.
        expect(first.thinkingOffPending, isTrue);
      },
    );

    test('the lowest level is kept even though it still reasons', () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = GoogleGenAiProvider(
        _config('floor', model: 'gemini-3-pro'),
        client: MockClient((request) async {
          bodies.add(_body(request));
          final config =
              bodies.last['generationConfig'] as Map<String, dynamic>;
          final thinking = config['thinkingConfig'] as Map<String, Object?>?;
          if (thinking != null && thinking.containsKey('thinkingBudget')) {
            return http.Response(
              jsonEncode({
                'error': {'message': 'thinking_budget is not supported.'},
              }),
              400,
            );
          }
          return _text(
            'hi',
            usage: const {'candidatesTokenCount': 2, 'thoughtsTokenCount': 90},
          );
        }),
      );

      final first = await provider.complete(systemPrompt: 's', userPrompt: 'u');
      await provider.complete(systemPrompt: 's', userPrompt: 'u');

      // Gemini 3 cannot stop thinking; "low" is the floor, not a failure.
      expect(first.thinkingOffPending, isFalse);
      expect((bodies.last['generationConfig'] as Map)['thinkingConfig'], {
        'thinkingLevel': 'low',
      });
    });
  });

  group('usage', () {
    test('thinking tokens are added to the completion count', () async {
      final result = await GoogleGenAiProvider(
        _config('usage'),
        client: MockClient(
          (_) async => _text(
            'done',
            usage: const {
              'promptTokenCount': 100,
              'candidatesTokenCount': 20,
              'thoughtsTokenCount': 500,
            },
          ),
        ),
      ).complete(systemPrompt: 's', userPrompt: 'u');

      // Google reports thinking beside the answer, never inside it. Reading
      // only candidatesTokenCount under-reports the most expensive part.
      expect(result.promptTokens, 100);
      expect(result.completionTokens, 520);
    });
  });

  group('blocked answers', () {
    test('a blocked prompt is an error, not an empty reply', () async {
      final provider = GoogleGenAiProvider(
        _config('promptblock'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'promptFeedback': {'blockReason': 'SAFETY'},
            }),
            200,
          ),
        ),
      );

      await expectLater(
        provider.complete(systemPrompt: 's', userPrompt: 'u'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('SAFETY'),
          ),
        ),
      );
    });

    test('a SAFETY finish reason discards the partial answer', () async {
      final provider = GoogleGenAiProvider(
        _config('answerblock'),
        client: MockClient(
          (_) async => _text('half an ans', finishReason: 'SAFETY'),
        ),
      );

      await expectLater(
        provider.complete(systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<AiException>()),
      );
    });

    for (final reason in [
      'UNEXPECTED_TOOL_CALL',
      'TOO_MANY_TOOL_CALLS',
      'MALFORMED_RESPONSE',
      'OTHER',
      'SOMETHING_NEW',
    ]) {
      test('$reason is a failure, not a short reply', () async {
        final provider = GoogleGenAiProvider(
          _config('finish-${reason.toLowerCase()}'),
          client: MockClient((_) async => _text('ok', finishReason: reason)),
        );
        await expectLater(
          provider.chat(messages: const [UserMessage('u')], tools: const []),
          throwsA(
            isA<AiException>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
        );
      });
    }

    test('a catch-all stop leaves tool support undecided', () async {
      final probe = await AiConnectionCheck.probeTools(
        GoogleGenAiProvider(
          _config('finish-other-probe'),
          client: MockClient((_) async => _text('', finishReason: 'OTHER')),
        ),
      );
      expect(probe.outcome, ToolProbe.inconclusive);
    });

    test('a missing thought signature blames the request', () async {
      final provider = GoogleGenAiProvider(
        _config('finish-signature'),
        client: MockClient(
          (_) async => _text('', finishReason: 'MISSING_THOUGHT_SIGNATURE'),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('not a problem with your files'),
          ),
        ),
      );
    });

    test('MAX_TOKENS is a usable answer, reported as truncated', () async {
      final result = await GoogleGenAiProvider(
        _config('capped'),
        client: MockClient(
          (_) async => _text('as far as it got', finishReason: 'MAX_TOKENS'),
        ),
      ).complete(systemPrompt: 's', userPrompt: 'u');

      expect(result.text, 'as far as it got');
      expect(result.truncated, isTrue);
    });
  });

  group('address', () {
    Future<Uri> sent(String endpoint) async {
      late Uri seen;
      await GoogleGenAiProvider(
        AiConfig(
          provider: AiProviderType.googleGenAi,
          endpoint: endpoint,
          apiKey: 'secret-key-value',
          model: 'gemini-3-flash',
        ),
        client: MockClient((request) async {
          seen = request.url;
          return _text('ok');
        }),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      return seen;
    }

    test('a pasted models URL is cut back to its root', () async {
      const expected =
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-3-flash:streamGenerateContent?alt=sse';
      for (final pasted in [
        'https://generativelanguage.googleapis.com/v1beta/models',
        'https://generativelanguage.googleapis.com/v1beta/models/',
        'https://generativelanguage.googleapis.com/v1beta/models/'
            'gemini-3-flash:generateContent',
        'https://generativelanguage.googleapis.com/v1beta/models/'
            'gemini-3-flash:streamGenerateContent?alt=sse',
      ]) {
        expect((await sent(pasted)).toString(), expected, reason: pasted);
      }
      // A key pasted into the URL is not sent along with it.
      expect(
        (await sent(
          'https://generativelanguage.googleapis.com/v1beta?key=AIza-pasted',
        )).toString(),
        expected,
      );
      // A host is not a path segment.
      expect(
        (await sent('http://models')).toString(),
        'http://models/v1beta/models/'
        'gemini-3-flash:streamGenerateContent?alt=sse',
      );
    });

    test('a 404 says where it went, and never the key', () async {
      final provider = GoogleGenAiProvider(
        _config('google-404.example'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 404, 'message': 'models/x is not found'},
            }),
            404,
          ),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>()
              .having(
                (e) => e.message,
                'message',
                contains(
                  'POST https://google-404.example/v1beta/models/'
                  'gemini-2.5-flash:streamGenerateContent',
                ),
              )
              .having((e) => e.message, 'message', isNot(contains('?')))
              .having((e) => e.message, 'message', isNot(contains('key'))),
        ),
      );
    });

    test('any other refusal carries no URL', () async {
      // Learning reads words in the message; a relay path is not one.
      final provider = GoogleGenAiProvider(
        _config('google-400.example'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 400, 'message': 'bad request'},
            }),
            400,
          ),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            'HTTP 400: bad request',
          ),
        ),
      );
    });
  });

  group('transport failures', () {
    test('a network error never carries the API key', () async {
      final uri = Uri.parse(
        'https://leak/v1beta/models/gemini-2.5-flash:streamGenerateContent'
        '?key=secret-key-value',
      );
      final provider = GoogleGenAiProvider(
        _config('leak'),
        client: MockClient((_) async {
          // What package:http raises when the socket fails: its toString()
          // carries the request URL, and Google puts the key in that URL.
          throw http.ClientException('Connection reset by peer', uri);
        }),
      );

      await expectLater(
        provider.complete(systemPrompt: 's', userPrompt: 'u'),
        throwsA(
          isA<AiNetworkException>()
              .having(
                (e) => e.message,
                'message',
                isNot(contains('secret-key-value')),
              )
              .having((e) => e.message, 'message', isNot(contains('key=')))
              .having(
                (e) => e.message,
                'message',
                contains('Connection reset'),
              ),
        ),
      );
    });

    test('the request log never holds the key', () async {
      final dir = await Directory.systemTemp.createTemp('gemini_log');
      addTearDown(() async {
        ApiLog.instance
          ..enabled = false
          ..directory = null;
        await dir.delete(recursive: true);
      });
      ApiLog.instance
        ..directory = dir
        ..enabled = true;

      await GoogleGenAiProvider(
        _config('logged-gemini'),
        client: MockClient((_) async => _text('ok')),
      ).chat(messages: const [UserMessage('u')], tools: const []);
      await ApiLog.instance.flush();

      final text = await ApiLog.instance.currentFile!.readAsString();
      expect(text, contains('"protocol":"gemini"'));
      expect(text, isNot(contains('secret-key-value')));
      expect(text, isNot(contains('key=')));
    });

    test('the key travels in a header, never in the URL', () async {
      final seen = <http.BaseRequest>[];
      final provider = GoogleGenAiProvider(
        _config('key-header'),
        client: MockClient((request) async {
          seen.add(request);
          return request.method == 'GET'
              ? http.Response('{}', 404)
              : _text('ok');
        }),
      );

      await provider.chat(messages: const [UserMessage('u')], tools: const []);
      await provider.detectLimits();

      expect(seen, hasLength(2));
      for (final request in seen) {
        expect(request.url.queryParameters.containsKey('key'), isFalse);
        expect(request.headers['x-goog-api-key'], 'secret-key-value');
      }
    });

    test('a socket failure is reported by its cause alone', () {
      final described = AiHttp.describeTransportError(
        const SocketException(
          'Connection failed',
          osError: OSError('Connection refused', 61),
        ),
      );
      expect(described, contains('Connection refused'));
      expect(described, isNot(contains('uri')));
    });

    test('a generation timeout is not retried', () async {
      var calls = 0;
      final provider = GoogleGenAiProvider(
        _config('slow'),
        firstEventTimeout: const Duration(milliseconds: 30),
        client: MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _text('too late');
        }),
      );

      await expectLater(
        provider.complete(systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<AiNetworkException>()),
      );
      // Future.timeout does not close the socket, so a retry would start a
      // second generation beside the one the server is still running.
      expect(calls, 1);
    });
  });

  group('streaming', () {
    String event(String text, {String? finish}) =>
        'data: ${jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
              'finishReason': ?finish,
            },
          ],
        })}\n\n';
    Future<ChatResult> read(String host, String body) => GoogleGenAiProvider(
      _config(host),
      client: MockClient(
        (_) async => http.Response(
          body,
          200,
          headers: const {'content-type': 'text/event-stream'},
        ),
      ),
    ).chat(messages: const [UserMessage('u')], tools: const []);

    test('a skipped event fails the reply it may have been part of', () async {
      await expectLater(
        read(
          'gemini-skipped.example',
          '${event('Hel')}data: {"candidates": \n\n'
              '${event('lo', finish: 'STOP')}',
        ),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('an empty data line or a [DONE] is no event', () async {
      final result = await read(
        'gemini-empty-data.example',
        'data:\n\n${event('Hel')}${event('lo', finish: 'STOP')}'
            'data: [DONE]\n\n',
      );
      expect(result.text, 'Hello');
    });

    http.Response sse(List<Map<String, Object?>> events) => http.Response(
      [for (final e in events) 'data: ${jsonEncode(e)}\n\n'].join(),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );

    test('asks for a stream and appends each event\'s parts', () async {
      late http.BaseRequest seen;
      final provider = GoogleGenAiProvider(
        _config('sse'),
        client: MockClient((request) async {
          seen = request;
          return sse([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Hel'},
                    ],
                  },
                },
              ],
            },
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'lo'},
                      {
                        'functionCall': {
                          'name': 'f',
                          'args': {'a': 1},
                        },
                        'thoughtSignature': 'sig',
                      },
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
              'usageMetadata': {
                'promptTokenCount': 7,
                'candidatesTokenCount': 3,
                'thoughtsTokenCount': 2,
              },
            },
          ]);
        }),
      );

      final result = await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [],
      );

      expect(seen.url.path, endsWith(':streamGenerateContent'));
      expect(seen.url.queryParameters['alt'], 'sse');
      expect(result.text, 'Hello');
      expect(result.toolCalls.single.name, 'f');
      expect(result.raw?.parts, hasLength(3));
      expect(result.promptTokens, 7);
      expect(result.completionTokens, 5);
      expect(result.finishReason, 'STOP');
    });

    test('a stream that ends without a finish reason was cut off', () async {
      final provider = GoogleGenAiProvider(
        _config('sse-cut'),
        client: MockClient(
          (_) async => sse([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'half an'},
                    ],
                  },
                },
              ],
            },
          ]),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('an event split over data lines, after a comment, is read', () async {
      final event = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'joined'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      });
      // SSE joins an event's data lines with a newline, which is only valid
      // JSON between tokens — where a real sender splits.
      final half = event.indexOf('[') + 1;
      final provider = GoogleGenAiProvider(
        _config('sse-multiline'),
        client: MockClient(
          (_) async => http.Response(
            ': keep-alive\n\ndata: ${event.substring(0, half)}\n'
            'data: ${event.substring(half)}\n\n',
            200,
          ),
        ),
      );
      final result = await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [],
      );
      expect(result.text, 'joined');
    });

    test('a relay that answers with a JSON array is read too', () async {
      final provider = GoogleGenAiProvider(
        _config('array'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'a'},
                      ],
                    },
                  },
                ],
              },
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'b'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              },
            ]),
            200,
          ),
        ),
      );
      final result = await provider.chat(
        messages: const [UserMessage('u')],
        tools: const [],
      );
      expect(result.text, 'ab');
    });

    test('a failed finish in the last event throws', () async {
      final provider = GoogleGenAiProvider(
        _config('sse-safety'),
        client: MockClient(
          (_) async => sse([
            {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'partial'},
                    ],
                  },
                },
              ],
            },
            {
              'candidates': [
                {'finishReason': 'SAFETY'},
              ],
            },
          ]),
        ),
      );
      await expectLater(
        provider.chat(messages: const [UserMessage('u')], tools: const []),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('request shape', () {
    test('an image goes as inlineData', () {
      final contents = GoogleGenAiProvider.contents([
        UserMessage(
          'look',
          images: [
            ImagePart(bytes: Uint8List.fromList([1, 2, 3])),
          ],
        ),
      ]);
      expect((contents.single['parts'] as List).last, {
        'inlineData': {'mimeType': 'image/jpeg', 'data': 'AQID'},
      });
    });

    test('the system message travels as systemInstruction', () async {
      late http.BaseRequest seen;
      await GoogleGenAiProvider(
        _config('system'),
        client: MockClient((request) async {
          seen = request;
          return _text('hi');
        }),
      ).complete(systemPrompt: 'be brief', userPrompt: 'hello');

      final body = _body(seen);
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'be brief'},
        ],
      });
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'hello'},
          ],
        },
      ]);
    });

    test('a tool call comes back with its parts kept verbatim', () async {
      final provider = GoogleGenAiProvider(
        _config('tools'),
        client: MockClient(
          (_) async => _ok({
            'parts': [
              {'thought': true, 'text': 'thinking…'},
              {
                'functionCall': {
                  'name': 'submit',
                  'args': {'title': 'Frieren'},
                },
                'thoughtSignature': 'sig-abc',
              },
            ],
          }),
        ),
      );

      final result = await provider.chat(
        messages: const [UserMessage('go')],
        tools: const [
          ToolDefinition(
            name: 'submit',
            description: 'Submits.',
            parameters: {'type': 'object', 'properties': {}},
          ),
        ],
      );

      // Thought parts are reasoning, not the answer.
      expect(result.text, '');
      expect(result.toolCalls.single.name, 'submit');
      expect(result.toolCalls.single.decodedArguments, {'title': 'Frieren'});
      // The signature has to return unchanged on the next turn.
      expect(result.raw?.parts, hasLength(2));
      expect((result.raw!.parts[1] as Map)['thoughtSignature'], 'sig-abc');
    });
  });
}
