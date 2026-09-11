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

sealed class ChatMessage {
  const ChatMessage();
}

class SystemMessage extends ChatMessage {
  final String content;
  const SystemMessage(this.content);
}

class UserMessage extends ChatMessage {
  final String content;
  const UserMessage(this.content);
}

/// Reasoning kept with the turn that produced it, under the field name the
/// server used.
typedef ReasoningPassback = ({String field, String text});

class AssistantMessage extends ChatMessage {
  final String content;
  final List<ToolCall> toolCalls;

  /// Sent back only with tool calls. DeepSeek-style servers reject a tool-call
  /// turn that lacks its reasoning and reject reasoning on a turn without tool
  /// calls; attaching it exactly when there are calls satisfies both.
  final ReasoningPassback? reasoning;

  /// Gemini's raw model parts, which carry thought signatures that must return
  /// unchanged.
  final List<Object?>? geminiParts;

  const AssistantMessage({
    this.content = '',
    this.toolCalls = const [],
    this.reasoning,
    this.geminiParts,
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

  /// The arguments exactly as the model wrote them.
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
      return null;
    }
  }
}

/// What one turn returned: text, tool calls, or both.
class ChatResult {
  final String text;
  final List<ToolCall> toolCalls;
  final ReasoningPassback? reasoning;
  final List<Object?>? geminiParts;
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
    this.geminiParts,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
    this.reasoned = false,
    this.thinkingOffPending = false,
  });

  bool get truncated => switch (finishReason?.toLowerCase()) {
    'length' || 'max_tokens' => true,
    _ => false,
  };

  /// The assistant turn to append to the history.
  AssistantMessage toMessage() => AssistantMessage(
    content: text,
    toolCalls: toolCalls,
    reasoning: toolCalls.isEmpty ? null : reasoning,
    geminiParts: geminiParts,
  );

  ChatResult withThinkingOffPending(bool pending) => ChatResult(
    text: text,
    toolCalls: toolCalls,
    reasoning: reasoning,
    geminiParts: geminiParts,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    finishReason: finishReason,
    reasoned: reasoned,
    thinkingOffPending: pending,
  );
}
