/// The Settings "Test connection" button: one real, tiny completion.
///
/// It used to list `GET /models`, which proves the server is up and accepts
/// the key but says nothing about whether a generation request goes through —
/// and that is exactly where compatible servers differ. LM Studio listed its
/// models happily and then rejected every organize request over
/// `response_format`, so the test passed while the feature failed. Going
/// through [AiProvider.complete] sends the same body, JSON mode and fallbacks
/// the organize and scrape pipelines use.
library;

import 'dart:convert';

import 'ai_cancel_token.dart';
import 'ai_provider.dart';

class AiConnectionCheckResult {
  /// What the model said, unwrapped from its JSON when it followed the
  /// instruction. Empty when it returned nothing.
  final String reply;
  final Duration latency;
  final int promptTokens;
  final int completionTokens;

  /// The reply stopped at the output cap — typically a reasoning model that
  /// spent the whole budget thinking. The connection works; the cap is too
  /// tight for real requests.
  final bool truncated;

  /// What the server reports about the model, looked up alongside the test.
  final ModelLimits limits;

  const AiConnectionCheckResult({
    required this.reply,
    required this.latency,
    required this.promptTokens,
    required this.completionTokens,
    required this.truncated,
    required this.limits,
  });
}

class AiConnectionCheck {
  AiConnectionCheck._();

  /// Generous for a greeting, because a local server loads the model on its
  /// first request and a large one can take most of a minute to arrive.
  static const timeout = Duration(seconds: 90);

  static const systemPrompt =
      'You are a connectivity check. Reply with a JSON object of the form '
      '{"reply": "<a short greeting>"} and nothing else.';

  static const userPrompt = 'Hello! Please greet me back in a few words.';

  /// Sends the greeting through [provider]. Throws whatever the request threw.
  static Future<AiConnectionCheckResult> run(AiProvider provider) async {
    final token = AiCancelToken();
    // Discovery never throws, so it can run alongside without a handler.
    final limits = provider.detectLimits();
    final stopwatch = Stopwatch()..start();
    try {
      final response = await provider
          .complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            cancelToken: token,
          )
          .timeout(
            timeout,
            onTimeout: () {
              token.cancel();
              throw AiException('No reply within ${timeout.inSeconds} s.');
            },
          );
      stopwatch.stop();
      return AiConnectionCheckResult(
        reply: replyText(response.text),
        latency: stopwatch.elapsed,
        promptTokens: response.promptTokens,
        completionTokens: response.completionTokens,
        truncated: response.truncated,
        limits: await limits,
      );
    } finally {
      token.dispose();
    }
  }

  /// The greeting out of `{"reply": …}`, or the raw text when the model
  /// ignored the format — which still proves it answered.
  static String replyText(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start != -1 && end > start) {
      try {
        final json = jsonDecode(raw.substring(start, end + 1));
        if (json is Map && json['reply'] is String) {
          return (json['reply'] as String).trim();
        }
      } on FormatException {
        // Not the requested shape; the raw text below still counts.
      }
    }
    return raw.trim();
  }
}
