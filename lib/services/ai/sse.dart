/// Reading a server-sent event stream the way every relay actually sends it.
///
/// An event is its `data:` lines joined by newlines, ended by a blank line;
/// `event:`, `id:`, `retry:` and `:` comment lines carry nothing a provider
/// needs — but a stream may open with any of them (OpenRouter sends
/// `: OPENROUTER PROCESSING` keep-alives before the first event), so they
/// must not decide whether the body is a stream at all. A body that is not a
/// stream — a relay that ignored `stream: true` — comes back whole as
/// [SseRead.plain].
///
/// An event whose data does not parse is skipped and counted in
/// [SseRead.skipped], never thrown here: whether the reply can stand without
/// it depends on the protocol, so each adapter decides. An empty `data:` is
/// no event at all.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_cancel_token.dart';
import 'ai_http.dart';
import 'ai_provider.dart';

typedef SseRead = ({
  List<Map<dynamic, dynamic>> events,
  String? plain,
  int skipped,
});

abstract final class Sse {
  /// Reads [res] to its end, timed on silence: [firstEventTimeout] until
  /// anything arrives, [idleTimeout] for any gap after. Closing the stream on
  /// a timeout or cancel is what stops the server generating.
  ///
  /// [onEvent] sees each event as it is decoded and may throw to end the
  /// read (an error event); [stopAt] ends it early (`[DONE]`).
  static Future<SseRead> read(
    http.StreamedResponse res, {
    required Duration firstEventTimeout,
    required Duration idleTimeout,
    AiCancelToken? cancelToken,
    void Function(Map<dynamic, dynamic> event)? onEvent,
    String stopAt = '[DONE]',
  }) async {
    final lines = StreamIterator(
      res.stream.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final events = <Map<dynamic, dynamic>>[];
    final plain = StringBuffer();
    final data = <String>[];
    bool? sse =
        (res.headers['content-type'] ?? '').contains('text/event-stream')
        ? true
        : null;
    var started = false;
    var stopped = false;
    var skipped = 0;

    // An event that does not parse is counted, not thrown: the adapter knows
    // whether the one dropped could have been part of the answer.
    void flush() {
      if (data.isEmpty) return;
      final joined = data.join('\n');
      data.clear();
      if (joined.trim().isEmpty) return;
      if (joined.trim() == stopAt) {
        stopped = true;
        return;
      }
      final Object? event;
      try {
        event = jsonDecode(joined);
      } on FormatException {
        skipped++;
        return;
      }
      if (event is Map) {
        events.add(event);
        onEvent?.call(event);
      }
    }

    try {
      while (!stopped) {
        final bool more;
        try {
          more = await lines.moveNext().timeout(
            started ? idleTimeout : firstEventTimeout,
          );
        } on TimeoutException {
          throw AiTimeoutException(
            started
                ? 'The server stopped sending for ${duration(idleTimeout)} '
                      'partway through the reply.'
                : noResponse(firstEventTimeout),
          );
        }
        if (!more) break;
        final line = lines.current;
        if (line.trim().isEmpty) {
          if (sse == true) flush();
          continue;
        }
        started = true;
        final framing =
            line.startsWith(':') ||
            line.startsWith('event:') ||
            line.startsWith('id:') ||
            line.startsWith('retry:');
        if (line.startsWith('data:')) {
          sse = true;
          data.add(line.substring(5).trimLeft());
        } else if (framing) {
          sse ??= true;
        } else if (sse == true) {
          // Not a field this reader knows; ignored, as the SSE spec says.
          continue;
        } else {
          sse = false;
          plain.writeln(line);
        }
      }
      if (sse == true) flush();
    } on AiException {
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) throw const AiCancelled();
      throw AiNetworkException(AiHttp.describeTransportError(e));
    } finally {
      await lines.cancel();
    }
    return (
      events: events,
      plain: sse == true ? null : plain.toString(),
      skipped: skipped,
    );
  }

  /// What an adapter throws when [SseRead.skipped] events could have held
  /// part of the answer.
  static const malformed = AiNetworkException(
    'The server sent a malformed stream event.',
  );

  static String noResponse(Duration timeout) =>
      'No response from the server within ${duration(timeout)}.';

  static String duration(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  /// What the API log keeps of a reply.
  static Map<String, Object?> summarise(ChatResult result) => {
    'finish_reason': result.finishReason,
    'text': result.text,
    if (result.toolCalls.isNotEmpty)
      'tool_calls': [
        for (final call in result.toolCalls)
          {'name': call.name, 'arguments': call.arguments},
      ],
    if (result.reasoned) 'reasoned': true,
    'usage': {
      'prompt': result.promptTokens,
      'completion': result.completionTokens,
    },
  };
}
