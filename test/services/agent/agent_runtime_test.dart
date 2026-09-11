import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/agent/agent_runtime.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai/chat.dart';

import '../../helpers/ai.dart';

class _Tally {
  int count = 0;
  AiCancelToken? cancelOnAdd;
}

class _Add extends AgentTool<_Tally> {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'add',
    description: 'Adds to the count.',
    parameters: {
      'type': 'object',
      'properties': {
        'by': {'type': 'integer'},
      },
      'required': ['by'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, _Tally context) {
    final by = arguments['by'];
    if (by is! int) throw const ToolError('by must be an integer.');
    context.count += by;
    context.cancelOnAdd?.cancel();
    return 'count is ${context.count}';
  }
}

List<ChatMessage> _seed() => [
  const SystemMessage('Count to the target.'),
  const UserMessage('Reach 2.'),
];

Future<AgentRunResult> _run(
  ScriptedChatProvider provider,
  _Tally tally, {
  List<ChatMessage>? messages,
  int maxRounds = 6,
  bool Function()? isDone,
  String? Function()? nudge,
  AiCancelToken? cancelToken,
}) => AgentRuntime.run<_Tally>(
  provider: provider,
  messages: messages ?? _seed(),
  tools: [_Add()],
  context: tally,
  maxRounds: maxRounds,
  isDone: isDone ?? () => tally.count >= 2,
  nudge: nudge,
  cancelToken: cancelToken,
);

void main() {
  test(
    'the run ends as soon as the task is done, with no closing turn',
    () async {
      final provider = ScriptedChatProvider([
        (_) => toolTurn([
          ('add', {'by': 2}),
        ]),
      ]);
      final tally = _Tally();

      final result = await _run(provider, tally);

      expect(result.outcome, AgentOutcome.completed);
      expect(provider.calls, 1);
      expect(result.promptTokens, 10);
    },
  );

  test(
    'every call gets its reply, in order, after the assistant turn',
    () async {
      final provider = ScriptedChatProvider([
        (_) => toolTurn([
          ('add', {'by': 1}),
          ('add', {'by': 1}),
        ]),
      ]);
      final messages = _seed();

      await _run(provider, _Tally(), messages: messages);

      expect(messages[2], isA<AssistantMessage>());
      final replies = messages.skip(3).cast<ToolResultMessage>().toList();
      expect(replies.map((r) => r.toolCallId), ['c0', 'c1']);
      expect(replies.last.content, 'count is 2');
    },
  );

  test('a rejected call reaches the model, which can correct it', () async {
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        ('add', {'by': 'two'}),
      ]),
      (_) => toolTurn([
        ('add', {'by': 2}),
      ]),
    ]);

    final result = await _run(provider, _Tally());

    expect(result.outcome, AgentOutcome.completed);
    final feedback = provider.seen[1].last as ToolResultMessage;
    expect(feedback.content, 'Error: by must be an integer.');
  });

  test('an unknown tool and non-JSON arguments come back as errors', () async {
    final provider = ScriptedChatProvider([
      (_) => ChatResult(
        toolCalls: [
          const ToolCall(id: 'a', name: 'subtract', arguments: '{}'),
          const ToolCall(id: 'b', name: 'add', arguments: 'by=2'),
        ],
      ),
      (_) => toolTurn([
        ('add', {'by': 2}),
      ]),
    ]);

    await _run(provider, _Tally());

    final replies = provider.seen[1].skip(3).cast<ToolResultMessage>();
    expect(replies.first.content, contains('no tool named "subtract"'));
    expect(replies.last.content, contains('not a JSON object'));
  });

  test(
    'a model that stops early is reminded, then its stop is accepted',
    () async {
      final provider = ScriptedChatProvider([(_) => textTurn('All done!')]);

      final result = await _run(
        provider,
        _Tally(),
        isDone: () => false,
        nudge: () => 'The count is not there yet. Call add.',
      );

      expect(result.outcome, AgentOutcome.stopped);
      expect(provider.calls, 3, reason: 'one turn plus two reminders');
      expect(
        provider.seen[1].last,
        isA<UserMessage>().having(
          (m) => m.content,
          'content',
          'The count is not there yet. Call add.',
        ),
      );
    },
  );

  test('rounds of nothing but failed calls end the run', () async {
    final provider = ScriptedChatProvider([
      (_) => toolTurn([('multiply', <String, Object?>{})]),
    ]);

    final result = await _run(provider, _Tally(), isDone: () => false);

    expect(result.outcome, AgentOutcome.erratic);
    expect(provider.calls, AgentRuntime.maxErraticRounds);
  });

  test('the round limit ends a run that never finishes', () async {
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        ('add', {'by': 1}),
      ]),
    ]);

    final result = await _run(
      provider,
      _Tally(),
      maxRounds: 4,
      isDone: () => false,
    );

    expect(result.outcome, AgentOutcome.exhausted);
    expect(provider.calls, 4);
  });

  test(
    'a cancel mid-round answers the skipped calls before throwing',
    () async {
      final token = AiCancelToken();
      final tally = _Tally()..cancelOnAdd = token;
      final provider = ScriptedChatProvider([
        (_) => toolTurn([
          ('add', {'by': 1}),
          ('add', {'by': 1}),
          ('add', {'by': 1}),
        ]),
      ]);
      final messages = _seed();

      await expectLater(
        _run(provider, tally, messages: messages, cancelToken: token),
        throwsA(isA<AiCancelled>()),
      );

      final replies = messages.whereType<ToolResultMessage>().toList();
      expect(replies.map((r) => r.toolCallId), ['c0', 'c1', 'c2']);
      expect(replies.skip(1).map((r) => r.content), [
        AgentRuntime.notRunResult,
        AgentRuntime.notRunResult,
      ]);
      expect(tally.count, 1);
    },
  );

  group('trimHistory', () {
    test('shrinks the oldest tool results first and keeps every message', () {
      final big = 'x' * 6000;
      final messages = <ChatMessage>[
        const SystemMessage('system'),
        const UserMessage('task'),
        AssistantMessage(
          toolCalls: [
            ToolCall(id: 'a', name: 'read', arguments: jsonEncode({})),
          ],
        ),
        ToolResultMessage(toolCallId: 'a', name: 'read', content: big),
        AssistantMessage(
          toolCalls: [
            ToolCall(id: 'b', name: 'read', arguments: jsonEncode({})),
          ],
        ),
        ToolResultMessage(toolCallId: 'b', name: 'read', content: big),
      ];

      final shrunk = AgentRuntime.trimHistory(messages, 4096, reserve: 1000);

      expect(shrunk, 1);
      expect(messages, hasLength(6));
      expect(
        (messages[3] as ToolResultMessage).content,
        AgentRuntime.droppedResult,
      );
      expect((messages[5] as ToolResultMessage).content, big);
      expect((messages[0] as SystemMessage).content, 'system');
    });

    test('leaves a history that fits alone', () {
      final messages = _seed();
      expect(AgentRuntime.trimHistory(messages, 4096), 0);
    });
  });
}
