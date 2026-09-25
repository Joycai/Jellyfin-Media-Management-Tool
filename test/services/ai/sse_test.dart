import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/sse.dart';

http.StreamedResponse _body(String text, {bool eventStream = false}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(text)),
      200,
      headers: {if (eventStream) 'content-type': 'text/event-stream'},
    );

Future<SseRead> _read(String text, {bool eventStream = false}) => Sse.read(
  _body(text, eventStream: eventStream),
  firstEventTimeout: const Duration(seconds: 5),
  idleTimeout: const Duration(seconds: 5),
);

void main() {
  group('silence', () {
    Future<SseRead> silent(List<String> before) => Sse.read(
      http.StreamedResponse(
        // What arrives, then nothing, and the connection never closes.
        Stream<List<int>>.multi((controller) {
          for (final chunk in before) {
            controller.add(utf8.encode(chunk));
          }
        }),
        200,
        headers: const {'content-type': 'text/event-stream'},
      ),
      firstEventTimeout: const Duration(milliseconds: 30),
      idleTimeout: const Duration(milliseconds: 30),
    );

    test('before the first event is a timeout', () async {
      await expectLater(silent(const []), throwsA(isA<AiTimeoutException>()));
    });

    test('partway through the reply is a timeout', () async {
      await expectLater(
        silent(const ['data: {"a": 1}\n\n']),
        throwsA(
          isA<AiTimeoutException>().having(
            (e) => e.message,
            'message',
            contains('partway'),
          ),
        ),
      );
    });
  });

  test('comments and event names do not make a stream plain text', () async {
    final read = await _read(
      ': keep-alive\n\nevent: x\nid: 1\ndata: {"a": 1}\n\ndata: [DONE]\n\n',
    );
    expect(read.plain, isNull);
    expect(read.events, [
      {'a': 1},
    ]);
  });

  test('an event split over data lines is joined', () async {
    final read = await _read('data: {"a":\ndata: 2}\n\n');
    expect(read.events.single, {'a': 2});
  });

  test('a body that is not a stream comes back whole', () async {
    final read = await _read('{"choices": []}\n');
    expect(read.plain?.trim(), '{"choices": []}');
    expect(read.events, isEmpty);
  });

  test('a malformed event is skipped and counted', () async {
    // The adapter decides whether the reply stands without it.
    final read = await _read(
      'data: {"a": \n\ndata: {"b": 2}\n\n',
      eventStream: true,
    );
    expect(read.events, [
      {'b': 2},
    ]);
    expect(read.skipped, 1);
  });

  test('an empty data line is no event at all', () async {
    final read = await _read(
      'data:\n\ndata: \n\ndata: {"b": 2}\n\n',
      eventStream: true,
    );
    expect(read.events, [
      {'b': 2},
    ]);
    expect(read.skipped, 0);
  });
}
