/// A multi-turn conversation with tool calls: the messages, the tools on
/// offer, and what one turn returns.
///
/// Shaped after OpenAI's Chat Completions, which every provider here converts
/// from. Anything a provider must send back verbatim on the next turn rides on
/// the assistant message itself, so it lives exactly as long as the history
/// does — rebuilt later, it would be missing precisely the parts a server
/// checks.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'ai_provider.dart' show AiProviderType;

sealed class ChatMessage {
  const ChatMessage();
}

class SystemMessage extends ChatMessage {
  final String content;
  const SystemMessage(this.content);
}

class UserMessage extends ChatMessage {
  final String content;

  /// Images sent with the text — video frames for a vision model. Each
  /// protocol has its own part shape; the adapters map them.
  final List<ImagePart> images;

  const UserMessage(this.content, {this.images = const []});
}

/// One inline image.
class ImagePart {
  final Uint8List bytes;
  final String mimeType;

  const ImagePart({required this.bytes, this.mimeType = 'image/jpeg'});

  String get base64 => base64Encode(bytes);

  /// `data:` URL, the form Chat Completions and Responses take.
  String get dataUrl => 'data:$mimeType;base64,$base64';
}

/// Reasoning kept with the turn that produced it, under the field name the
/// server used.
///
/// [encrypted] is Volcengine's encrypted chain of thought
/// (`encrypted_content`, KB 03 §3.2): its 2.1 models put only a summary in
/// `reasoning_content`, and a tool-call turn sent back without the original
/// leaves the model reasoning from the summary — no error, just worse
/// answers. It is never shown, goes back beside the summary, and alone when
/// the summary is empty.
///
/// Not bound to a model, unlike [ProviderTurn]: a Chat Completions history
/// lives for one agent run, and a run uses one configuration throughout. A
/// history that outlives a run or switches model would need a `model` here,
/// and stripping on a mismatch, for both fields.
typedef ReasoningPassback = ({String field, String text, String? encrypted});

/// An assistant turn exactly as a protocol returned it: Gemini's parts with
/// their thought signatures, Anthropic's content blocks with thinking and
/// signatures, the Responses API's output items with encrypted reasoning.
///
/// Sent back unchanged, and only to the protocol and model that produced it:
/// a signature is checked against the model that wrote it, so after a
/// switch the turn is rebuilt from its text and calls instead.
class ProviderTurn {
  final AiProviderType protocol;
  final String model;
  final List<Object?> parts;

  const ProviderTurn({
    required this.protocol,
    required this.model,
    required this.parts,
  });

  /// Whether this turn may go back verbatim to [protocol] on [model].
  bool fits(AiProviderType protocol, String model) =>
      this.protocol == protocol && this.model == model;
}

class AssistantMessage extends ChatMessage {
  final String content;
  final List<ToolCall> toolCalls;

  /// Sent back only with tool calls. DeepSeek-style servers reject a tool-call
  /// turn that lacks its reasoning and reject reasoning on a turn without tool
  /// calls; attaching it exactly when there are calls satisfies both.
  final ReasoningPassback? reasoning;

  /// The turn as the protocol returned it; see [ProviderTurn].
  final ProviderTurn? raw;

  const AssistantMessage({
    this.content = '',
    this.toolCalls = const [],
    this.reasoning,
    this.raw,
  });
}

class ToolResultMessage extends ChatMessage {
  final String toolCallId;
  final String name;
  final String content;

  const ToolResultMessage({
    required this.toolCallId,
    required this.name,
    required this.content,
  });
}

class ToolDefinition {
  final String name;
  final String description;

  /// JSON Schema for the arguments. Kept to the subset every provider accepts:
  /// `type`, `properties`, `required`, `items`, `enum`, `description`.
  final Map<String, Object?> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

class ToolCall {
  final String id;
  final String name;

  /// The arguments as the model wrote them, or merged into one object when
  /// it wrote several back to back (see [mergeConcatenated]).
  final String arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The arguments decoded, or null when the model wrote something that is not
  /// a JSON object — the caller tells the model so rather than guessing.
  Map<String, dynamic>? get decodedArguments {
    final raw = arguments.trim();
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return mergeConcatenated(raw);
    }
  }

  /// [raw] as it should be sent back: unchanged, unless it is several JSON
  /// objects back to back, which become the one object they merge into. A
  /// relay translating the turn back to Messages must parse it, and would
  /// refuse the concatenation on the next request.
  static String normalizeArguments(String raw) {
    try {
      jsonDecode(raw);
      return raw;
    } on FormatException {
      final merged = mergeConcatenated(raw);
      return merged == null ? raw : jsonEncode(merged);
    }
  }

  /// Several JSON objects written back to back — `{}{"id": 1}`, what a
  /// relay-served Claude streams when it emits an empty input before the
  /// real one (KB pitfall 105) — merged left to right. Null unless [raw] is
  /// at least two objects with nothing but whitespace between them.
  static Map<String, dynamic>? mergeConcatenated(String raw) {
    final objects = <Map<String, dynamic>>[];
    var depth = 0;
    var start = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        if (depth == 0) return null;
        inString = true;
      } else if (char == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (char == '}') {
        if (depth == 0) return null;
        depth--;
        if (depth == 0) {
          try {
            final value = jsonDecode(raw.substring(start, i + 1));
            if (value is! Map<String, dynamic>) return null;
            objects.add(value);
          } on FormatException {
            return null;
          }
        }
      } else if (depth == 0 && char.trim().isNotEmpty) {
        return null;
      }
    }
    if (depth != 0 || objects.length < 2) return null;
    return {for (final object in objects) ...object};
  }
}

/// What one turn returned: text, tool calls, or both.
class ChatResult {
  final String text;
  final List<ToolCall> toolCalls;
  final ReasoningPassback? reasoning;
  final ProviderTurn? raw;
  final int promptTokens;
  final int completionTokens;
  final String? finishReason;

  /// The turn carried reasoning: reasoning deltas, reasoning tokens in the
  /// usage, thought parts, or a leading think block.
  final bool reasoned;

  /// Reasoning ran although the request asked for none, and the provider has
  /// another way of asking that the next request will use.
  final bool thinkingOffPending;

  const ChatResult({
    this.text = '',
    this.toolCalls = const [],
    this.reasoning,
    this.raw,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
    this.reasoned = false,
    this.thinkingOffPending = false,
  });

  bool get truncated => FinishReasons.isTruncation(finishReason);

  /// The assistant turn to append to the history.
  AssistantMessage toMessage() => AssistantMessage(
    content: text,
    toolCalls: toolCalls,
    reasoning: toolCalls.isEmpty ? null : reasoning,
    raw: raw,
  );

  ChatResult withThinkingOffPending(bool pending) => ChatResult(
    text: text,
    toolCalls: toolCalls,
    reasoning: reasoning,
    raw: raw,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    finishReason: finishReason,
    reasoned: reasoned,
    thinkingOffPending: pending,
  );
}

/// Why a reply that arrived with HTTP 200 must still not be used.
enum FinishFailure {
  /// A content filter stopped the reply: Azure and gateways say
  /// `content_filter`, Zhipu `sensitive`. Whatever arrived before is partial.
  filtered,

  /// The upstream model failed partway (Zhipu's `network_error`,
  /// OpenRouter's `error`). Nothing was learned about the model, so this
  /// counts as a transport failure.
  upstream,

  /// Prompt and reply together outgrew the model's context window. Unlike an
  /// output-cap cut, a larger output cap makes this worse: the history is
  /// what has to shrink.
  contextExceeded,
}

/// Reads the `finish_reason` values that are not a normal end.
///
/// Every one of them arrives inside a successful stream. Returning what came
/// before them hands the caller a partial answer it cannot tell from a whole,
/// and the agent loop reads the silence as "the model stopped calling tools"
/// — so the user goes off changing prompts and models when the reply was in
/// fact blocked, or cut short upstream.
abstract final class FinishReasons {
  /// The reply hit the output limit. It is real text, cut short.
  static bool isTruncation(String? reason) => switch (reason?.toLowerCase()) {
    'length' || 'max_tokens' => true,
    _ => false,
  };

  static FinishFailure? failure(String? reason) =>
      switch (reason?.toLowerCase()) {
        'content_filter' || 'sensitive' => FinishFailure.filtered,
        'network_error' || 'error' => FinishFailure.upstream,
        'model_context_window_exceeded' => FinishFailure.contextExceeded,
        _ => null,
      };
}
