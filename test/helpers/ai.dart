import 'dart:convert';

import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';

/// Replays canned model responses in order and records what it was asked.
///
/// The last reply repeats once the script runs out, so a test that only cares
/// about "the model keeps returning junk" can pass a single entry. Pass a
/// [config] with a context window to exercise prompt budgeting.
class ScriptedProvider implements AiProvider {
  final List<String> replies;
  final List<String> userPrompts = [];
  final List<String> systemPrompts = [];
  int calls = 0;

  @override
  final AiConfig config;

  ScriptedProvider(this.replies, {this.config = AiConfig.empty});

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) async {
    systemPrompts.add(systemPrompt);
    userPrompts.add(userPrompt);
    final reply = replies[calls.clamp(0, replies.length - 1)];
    calls++;
    return AiResponse(text: reply, promptTokens: 10, completionTokens: 5);
  }

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) async {
    final reply = replies[calls.clamp(0, replies.length - 1)];
    calls++;
    return ChatResult(text: reply, promptTokens: 10, completionTokens: 5);
  }

  @override
  Future<ModelLimits> detectLimits() async => ModelLimits.unknown;

  @override
  Future<ServerKind> detectServerKind() async => ServerKind.unknown;

  @override
  void forgetLearned() {}

  @override
  LearnedBehaviour get learned => LearnedBehaviour.empty;

  @override
  Future<RequestPreview?> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  }) async => null;
}

/// One scripted model turn: sees the history so far, returns the reply.
typedef ChatTurn = ChatResult Function(List<ChatMessage> messages);

/// Drives a tool-calling conversation from a script of turns, recording a
/// snapshot of the history each turn was given. The last turn repeats once
/// the script runs out.
class ScriptedChatProvider implements AiProvider {
  final List<ChatTurn> turns;
  final List<List<ChatMessage>> seen = [];
  final List<List<String>> offeredTools = [];

  @override
  final AiConfig config;

  ScriptedChatProvider(this.turns, {this.config = AiConfig.empty});

  int get calls => seen.length;

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) async {
    seen.add(List.of(messages));
    offeredTools.add([for (final tool in tools) tool.name]);
    final turn = turns[(seen.length - 1).clamp(0, turns.length - 1)];
    return turn(messages);
  }

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) => throw UnimplementedError('ScriptedChatProvider only chats');

  @override
  Future<ModelLimits> detectLimits() async => ModelLimits.unknown;

  @override
  Future<ServerKind> detectServerKind() async => ServerKind.unknown;

  @override
  void forgetLearned() {}

  @override
  LearnedBehaviour get learned => LearnedBehaviour.empty;

  @override
  Future<RequestPreview?> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  }) async => null;
}

/// A turn that calls tools: `[('add', {'by': 2}), …]`, with ids `c0`, `c1`, …
ChatResult toolTurn(List<(String, Map<String, Object?>)> calls) => ChatResult(
  toolCalls: [
    for (var i = 0; i < calls.length; i++)
      ToolCall(
        id: 'c$i',
        name: calls[i].$1,
        arguments: jsonEncode(calls[i].$2),
      ),
  ],
  promptTokens: 10,
  completionTokens: 5,
);

/// A turn that only answers in text.
ChatResult textTurn(String text) =>
    ChatResult(text: text, promptTokens: 10, completionTokens: 5);

/// A provider whose every request fails, for the paths that must tell a
/// transport failure from an answer.
class ThrowingChatProvider implements AiProvider {
  final Object Function() error;

  @override
  final AiConfig config;

  ThrowingChatProvider(this.error, {this.config = AiConfig.empty});

  @override
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  }) async => throw error();

  @override
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  }) async => throw error();

  @override
  Future<ModelLimits> detectLimits() async => ModelLimits.unknown;

  @override
  Future<ServerKind> detectServerKind() async => ServerKind.unknown;

  @override
  void forgetLearned() {}

  @override
  LearnedBehaviour get learned => LearnedBehaviour.empty;

  @override
  Future<RequestPreview?> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  }) async => null;
}
