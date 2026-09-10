/// Rough, deliberately pessimistic token arithmetic for keeping a conversation
/// inside a context window.
///
/// No tokenizer ships with the app and every model family counts differently,
/// so this over-estimates on purpose: three characters per token for ASCII
/// (English prose runs nearer four, markup and JSON nearer three) and one token
/// per character for everything else (Chinese and Japanese land between one and
/// 1.7 characters per token depending on the model). Guessing high costs a
/// tool result shrunk a little early; guessing low costs a prompt a local
/// server silently truncates from the front — system prompt first.
class TokenBudget {
  TokenBudget._();

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
}
