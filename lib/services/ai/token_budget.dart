import 'dart:math' as math;

import 'ai_provider.dart';

/// Rough, deliberately pessimistic token arithmetic for fitting prompts into a
/// context window.
///
/// No tokenizer ships with the app and every model family counts differently,
/// so this over-estimates on purpose: three characters per token for ASCII
/// (English prose runs nearer four, markup and JSON nearer three) and one token
/// per character for everything else (Chinese and Japanese land between one and
/// 1.7 characters per token depending on the model). Guessing high costs a
/// slightly smaller batch; guessing low costs a prompt a local server silently
/// truncates from the front — system prompt first.
class TokenBudget {
  TokenBudget._();

  /// Tokens a server's chat template wraps around the messages.
  static const int templateOverhead = 64;

  /// Floor for [inputAllowance]. A request squeezed below this is not worth
  /// much, but sending it still fails more legibly than skipping it would.
  static const int minimumInput = 256;

  static int estimate(String text) {
    var ascii = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (rune < 0x80) {
        ascii++;
      } else {
        other++;
      }
    }
    return (ascii / 3).ceil() + other;
  }

  /// The longest prefix of [text] estimated at no more than [maxTokens].
  /// [marker] is appended when anything was cut, and counts toward the limit.
  static String truncate(String text, int maxTokens, {String marker = ''}) {
    if (estimate(text) <= maxTokens) return text;
    final limit = maxTokens - estimate(marker);
    var ascii = 0;
    var other = 0;
    var end = 0;
    for (final rune in text.runes) {
      if (rune < 0x80) {
        ascii++;
      } else {
        other++;
      }
      if ((ascii / 3).ceil() + other > limit) break;
      end += rune > 0xFFFF ? 2 : 1;
    }
    return '${text.substring(0, end)}$marker';
  }

  /// Tokens the variable part of a request may use, or null when [config]
  /// names no context window — the caller then sends its natural size.
  ///
  /// [fixedPrompt] is everything sent regardless of the payload (system
  /// prompt, framing, instructions). [reservedOutput] is room kept for the
  /// reply when [AiConfig.maxOutputTokens] does not say; either way the reply
  /// never claims more than half the window. A tenth of the window is held
  /// back on top, because [estimate] is a guess.
  static int? inputAllowance(
    AiConfig config, {
    required String fixedPrompt,
    required int reservedOutput,
  }) {
    final window = config.contextWindow;
    if (window == null) return null;
    final output = math.min(
      config.maxOutputTokens ?? reservedOutput,
      window ~/ 2,
    );
    final usable =
        (window * 0.9).floor() -
        templateOverhead -
        estimate(fixedPrompt) -
        output;
    return math.max(minimumInput, usable);
  }
}
