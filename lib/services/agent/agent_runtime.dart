/// The one tool loop every agent task runs through.
///
/// Tasks differ in their tools, their context and what counts as done; the
/// loop does not. Keeping a single loop keeps its protocol obligations in one
/// place: every tool call gets a reply (a cancel stubs the calls it skipped
/// before throwing, because a history with an unanswered call is rejected on
/// every later turn), a bad call becomes text the model can correct rather
/// than an exception that ends the run, and when the history outgrows the
/// window old tool results are shrunk, never removed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../ai/ai_cancel_token.dart';
import '../ai/ai_provider.dart';
import '../ai/token_budget.dart';

/// Thrown by a tool to reject a call. The message goes back to the model, so
/// write it as the next step to take ("group g7 does not exist; call
/// list_groups"), not merely as what went wrong — a bare refusal gets the same
/// bad call again.
class ToolError implements Exception {
  final String message;
  const ToolError(this.message);

  @override
  String toString() => message;
}

/// One tool the model may call. [C] is the task's own state the tool reads
/// and writes.
abstract class AgentTool<C> {
  const AgentTool();

  ToolDefinition get definition;

  /// Runs one call and returns the text the model sees. Throw [ToolError] to
  /// reject it; any other exception is reported the same way.
  FutureOr<String> execute(Map<String, dynamic> arguments, C context);
}

sealed class AgentEvent {
  const AgentEvent();
}

class AgentRoundStarted extends AgentEvent {
  final int round;
  const AgentRoundStarted(this.round);
}

class AgentToolFinished extends AgentEvent {
  final String tool;
  final bool failed;
  const AgentToolFinished({required this.tool, required this.failed});
}

enum AgentOutcome {
  /// The task's own completion check passed.
  completed,

  /// The model stopped calling tools before the task was done, and would not
  /// continue when asked.
  stopped,

  /// The round limit ran out.
  exhausted,

  /// Several rounds in a row produced nothing but failed calls — a model that
  /// cannot drive these tools, where more rounds only burn tokens.
  erratic,

  /// Replies kept hitting the output limit. A reasoning model spends the cap
  /// on thinking and its tool arguments arrive cut off, which reads exactly
  /// like a model that cannot write JSON — but the fix is a larger output
  /// cap, not another model.
  truncated,
}

class AgentRunResult {
  final AgentOutcome outcome;
  final int rounds;
  final int promptTokens;
  final int completionTokens;

  const AgentRunResult({
    required this.outcome,
    required this.rounds,
    required this.promptTokens,
    required this.completionTokens,
  });

  bool get completed => outcome == AgentOutcome.completed;
}

abstract final class AgentRuntime {
  /// The reply a skipped call gets when a cancel lands mid-round.
  static const notRunResult = '[not run — the task was cancelled]';

  /// What a shrunk tool result reads.
  static const droppedResult =
      "[earlier tool result dropped to stay within the model's context window]";

  static const maxErraticRounds = 3;

  /// Cut-off rounds in a row before the run ends as [AgentOutcome.truncated].
  static const maxTruncatedRounds = 2;

  /// What to tell the user when a run ends as [AgentOutcome.truncated].
  static String truncatedMessage(int? maxOutputTokens) =>
      maxOutputTokens == null
      ? 'The model kept hitting its output limit before finishing a reply. '
            'Set a larger maximum output in the AI service settings.'
      : 'The model kept hitting its output limit ($maxOutputTokens tokens) '
            'before finishing a reply. Raise the maximum output in the AI '
            'service settings.';

  /// Runs [tools] against [provider] until [isDone], mutating [messages] in
  /// place so the caller holds the full transcript.
  ///
  /// When a round's calls leave the task done, the run ends there — a small
  /// model should not spend a turn announcing that it has finished — unless
  /// [stopWhenDone] is false, for tasks where the model may keep refining.
  /// When the model stops calling tools early, [nudge] supplies the reminder
  /// (return null to accept the stop), at most [maxNudges] times.
  static Future<AgentRunResult> run<C>({
    required AiProvider provider,
    required List<ChatMessage> messages,
    required List<AgentTool<C>> tools,
    required C context,
    required int maxRounds,
    required bool Function() isDone,
    String? Function()? nudge,
    int maxNudges = 2,
    bool stopWhenDone = true,
    int? contextWindow,
    AiCancelToken? cancelToken,
    void Function(AgentEvent event)? onEvent,
  }) async {
    final byName = {for (final tool in tools) tool.definition.name: tool};
    final definitions = [for (final tool in tools) tool.definition];
    var promptTokens = 0;
    var completionTokens = 0;
    var nudges = 0;
    var erraticRounds = 0;
    var truncatedRounds = 0;
    // Tool schemas are sent on every request but live outside `messages`, so
    // the budget has to be told about them or it under-counts by the size of
    // the whole tool list — which for organize is seven schemas.
    final toolOverhead = definitions.fold(
      0,
      (sum, tool) =>
          sum +
          16 +
          TokenBudget.estimate(tool.name) +
          TokenBudget.estimate(tool.description) +
          TokenBudget.estimate(jsonEncode(tool.parameters)),
    );
    // Messages that exist for exactly one request — see the retraction below.
    var pendingNudge = const <ChatMessage>[];

    AgentRunResult finish(AgentOutcome outcome, int rounds) => AgentRunResult(
      outcome: outcome,
      rounds: rounds,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );

    for (var round = 1; round <= maxRounds; round++) {
      cancelToken?.throwIfCancelled();
      onEvent?.call(AgentRoundStarted(round));
      if (contextWindow != null) {
        trimHistory(messages, contextWindow, overhead: toolOverhead);
      }

      final ChatResult reply;
      try {
        reply = await provider.chat(
          messages: messages,
          tools: definitions,
          cancelToken: cancelToken,
        );
      } finally {
        // A reminder is for the turn it was sent in and no longer. Left in the
        // history it becomes a standing instruction, and this one carries
        // state — "still undecided: g3, g7" is wrong the moment g3 is decided,
        // and the model obliges by submitting it again.
        //
        // The model's own "I am finished" turn goes with it. Retracting only
        // the reminder would leave that assistant turn answering a question
        // no longer in the history — and, once the model resumes calling
        // tools, two assistant turns in a row, which Gemini does not accept.
        // Neither message carries anything the loop needs, so the whole
        // exchange leaves no trace and the next round resumes from the last
        // tool result.
        for (final message in pendingNudge) {
          messages.remove(message);
        }
        pendingNudge = const [];
      }
      promptTokens += reply.promptTokens;
      completionTokens += reply.completionTokens;

      if (reply.toolCalls.isEmpty) {
        if (isDone()) return finish(AgentOutcome.completed, round);
        // A reply cut off mid-sentence is not a model that chose to stop, and
        // a reminder would be cut off at the same place. The same request is
        // asked again, once, the way a cut-off tool round is.
        if (reply.truncated) {
          truncatedRounds++;
          if (truncatedRounds >= maxTruncatedRounds) {
            return finish(AgentOutcome.truncated, round);
          }
          continue;
        }
        final reminder = nudges < maxNudges ? nudge?.call() : null;
        if (reminder == null) return finish(AgentOutcome.stopped, round);
        nudges++;
        // Retracted in the next round's `finally`, once it has been sent.
        pendingNudge = [
          if (reply.text.trim().isNotEmpty)
            AssistantMessage(content: reply.text),
          UserMessage(reminder),
        ];
        messages.addAll(pendingNudge);
        continue;
      }

      messages.add(reply.toMessage());
      var failures = 0;
      for (var i = 0; i < reply.toolCalls.length; i++) {
        final call = reply.toolCalls[i];
        if (cancelToken?.isCancelled ?? false) {
          for (final skipped in reply.toolCalls.skip(i)) {
            messages.add(
              ToolResultMessage(
                toolCallId: skipped.id,
                name: skipped.name,
                content: notRunResult,
              ),
            );
          }
          throw const AiCancelled();
        }
        final (content, failed) = await _execute(call, byName, context);
        if (failed) failures++;
        messages.add(
          ToolResultMessage(
            toolCallId: call.id,
            name: call.name,
            content: content,
          ),
        );
        onEvent?.call(AgentToolFinished(tool: call.name, failed: failed));
      }

      if (stopWhenDone && isDone()) {
        return finish(AgentOutcome.completed, round);
      }
      final allFailed = failures == reply.toolCalls.length;
      if (reply.truncated && allFailed) {
        // The calls failed because their arguments were cut off, which says
        // nothing about whether the model can drive the tools.
        truncatedRounds++;
        if (truncatedRounds >= maxTruncatedRounds) {
          return finish(AgentOutcome.truncated, round);
        }
        continue;
      }
      truncatedRounds = 0;
      erraticRounds = allFailed ? erraticRounds + 1 : 0;
      if (erraticRounds >= maxErraticRounds) {
        return finish(AgentOutcome.erratic, round);
      }
    }
    return finish(
      isDone() ? AgentOutcome.completed : AgentOutcome.exhausted,
      maxRounds,
    );
  }

  static Future<(String, bool)> _execute<C>(
    ToolCall call,
    Map<String, AgentTool<C>> tools,
    C context,
  ) async {
    final tool = tools[call.name];
    if (tool == null) {
      return (
        'Error: there is no tool named "${call.name}". '
            'The tools are: ${tools.keys.join(', ')}.',
        true,
      );
    }
    final arguments = call.decodedArguments;
    if (arguments == null) {
      return (
        'Error: the arguments were not a JSON object. '
            'Call ${call.name} again with valid JSON arguments.',
        true,
      );
    }
    try {
      return (await tool.execute(arguments, context), false);
    } on ToolError catch (e) {
      return ('Error: ${e.message}', true);
    } catch (e) {
      return ('Error: $e', true);
    }
  }

  /// Shrinks the oldest tool results until [messages] fit [contextWindow],
  /// keeping [reserve] tokens for the reply. Returns how many were shrunk.
  ///
  /// Only a result's content is replaced: removing the message would leave its
  /// call unanswered, which every provider rejects. System and user messages
  /// are never touched — if those alone overflow, that is a budgeting bug
  /// upstream, not something to hide here.
  ///
  /// [overhead] is what the request carries besides the messages — the tool
  /// schemas — and [reserve] what the reply needs. Both come off the ceiling,
  /// because the window has to hold the prompt *and* the answer: a budget that
  /// counts only the messages fits them exactly and then watches the server
  /// drop the front of the prompt to make room for the generation.
  static int trimHistory(
    List<ChatMessage> messages,
    int contextWindow, {
    int reserve = 2048,
    int overhead = 0,
  }) {
    final ceiling =
        (contextWindow * 0.9).floor() -
        math.min(reserve + overhead, contextWindow ~/ 2);
    var total = messages.fold(0, (sum, m) => sum + estimate(m));
    var shrunk = 0;
    for (var i = 0; i < messages.length && total > ceiling; i++) {
      final message = messages[i];
      if (message is! ToolResultMessage || message.content == droppedResult) {
        continue;
      }
      final replacement = ToolResultMessage(
        toolCallId: message.toolCallId,
        name: message.name,
        content: droppedResult,
      );
      total += estimate(replacement) - estimate(message);
      messages[i] = replacement;
      shrunk++;
    }
    return shrunk;
  }

  /// Rough tokens for one message, per [TokenBudget.estimate], plus a small
  /// allowance for the chat template's framing.
  static int estimate(ChatMessage message) =>
      8 +
      switch (message) {
        SystemMessage(:final content) ||
        UserMessage(:final content) => TokenBudget.estimate(content),
        AssistantMessage(:final content, :final toolCalls) =>
          TokenBudget.estimate(content) +
              toolCalls.fold(
                0,
                (sum, call) =>
                    sum +
                    TokenBudget.estimate(call.name) +
                    TokenBudget.estimate(call.arguments),
              ),
        ToolResultMessage(:final content) => TokenBudget.estimate(content),
      };
}

/// A tool's `page` argument as a 1-based page number. Small models send it as
/// a string, as nothing, or as zero; each of those means a page, not a failed
/// call worth a round.
int pageArgument(Object? value) {
  final page = switch (value) {
    num v => v.toInt(),
    String v => int.tryParse(v.trim()),
    _ => null,
  };
  return page == null || page < 1 ? 1 : page;
}
