/// The Settings "Test connection" button: one real, tiny completion, then a
/// check that the model calls tools.
///
/// It used to list `GET /models`, which proves the server is up and accepts
/// the key but says nothing about whether a generation request goes through —
/// and that is exactly where compatible servers differ. LM Studio listed its
/// models happily and then rejected every organize request over
/// `response_format`, so the test passed while the feature failed. Going
/// through [AiProvider.complete] sends the same body, JSON mode, sampling and
/// reasoning switches the pipelines use.
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

  /// The model reasoned on the final attempt. With thinking off, that means
  /// no way of turning it off worked on this server.
  final bool reasoned;

  /// The model called the test tool. Organize and scrape run as tool loops, so
  /// without this the model cannot run them.
  final bool supportsTools;

  /// Which software answered, for notes such as Ollama ignoring some sampling
  /// fields.
  final ServerKind serverKind;

  /// What the server reports about the model, looked up alongside the test.
  final ModelLimits limits;

  const AiConnectionCheckResult({
    required this.reply,
    required this.latency,
    required this.promptTokens,
    required this.completionTokens,
    required this.truncated,
    required this.reasoned,
    required this.supportsTools,
    required this.serverKind,
    required this.limits,
  });
}

class AiConnectionCheck {
  AiConnectionCheck._();

  /// Generous for a greeting, because a local server loads the model on its
  /// first request and a large one can take most of a minute to arrive.
  static const timeout = Duration(seconds: 90);

  /// Enough to walk every way a provider has of turning reasoning off.
  static const maxAttempts = 4;

  static const systemPrompt =
      'You are a connectivity check. Reply with a JSON object of the form '
      '{"reply": "<a short greeting>"} and nothing else.';

  static const userPrompt = 'Hello! Please greet me back in a few words.';

  static const toolProbe = ToolDefinition(
    name: 'report_greeting',
    description: 'Reports a short greeting back to the application.',
    parameters: {
      'type': 'object',
      'properties': {
        'greeting': {'type': 'string', 'description': 'A short greeting.'},
      },
      'required': ['greeting'],
    },
  );

  /// Sends the greeting through [provider], then checks tool calling. Throws
  /// whatever the greeting threw; a failed tool check only reports false.
  ///
  /// With thinking off, a reply that still reasons moves the provider on to
  /// its next way of asking. A greeting is cheap enough to find the one that
  /// works now, rather than on the user's first real task.
  static Future<AiConnectionCheckResult> run(AiProvider provider) async {
    final token = AiCancelToken();
    // Discovery never throws, so it can run alongside without a handler.
    final limits = provider.detectLimits();
    final serverKind = provider.detectServerKind();
    final stopwatch = Stopwatch()..start();
    try {
      late AiResponse response;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        response = await provider
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
        if (!response.thinkingOffPending) break;
      }
      stopwatch.stop();
      final supportsTools = await probeTools(provider, cancelToken: token);
      return AiConnectionCheckResult(
        reply: replyText(response.text),
        latency: stopwatch.elapsed,
        promptTokens: response.promptTokens,
        completionTokens: response.completionTokens,
        truncated: response.truncated,
        reasoned: response.reasoned,
        supportsTools: supportsTools,
        serverKind: await serverKind,
        limits: await limits,
      );
    } finally {
      token.dispose();
    }
  }

  /// Whether [provider]'s model calls a tool when the request plainly needs
  /// one.
  ///
  /// Asked twice: a small model sometimes answers the first time in prose even
  /// though it can call tools, and blocking every agent task on one stray
  /// reply would be worse than a second greeting. A server that rejects the
  /// `tools` field outright counts as unsupported.
  static Future<bool> probeTools(
    AiProvider provider, {
    AiCancelToken? cancelToken,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await provider
            .chat(
              messages: const [
                SystemMessage(
                  'You are a connectivity check. Call the report_greeting '
                  'tool with a short greeting. Do not reply in text.',
                ),
                UserMessage('Hello!'),
              ],
              tools: const [toolProbe],
              cancelToken: cancelToken,
            )
            .timeout(timeout);
        final called = result.toolCalls.any(
          (call) =>
              call.name == toolProbe.name && call.decodedArguments != null,
        );
        if (called) return true;
      } on AiCancelled {
        rethrow;
      } catch (_) {
        return false;
      }
    }
    return false;
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
