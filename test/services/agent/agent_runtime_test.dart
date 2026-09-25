import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/agent/agent_runtime.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';

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

class _Cancels extends AgentTool<_Tally> {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'cancel',
    description: 'Is cancelled while it runs.',
    parameters: {'type': 'object'},
  );

  @override
  String execute(Map<String, dynamic> arguments, _Tally context) =>
      throw const AiCancelled();
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

  test('a cancel inside a tool still answers every call', () async {
    final messages = _seed();
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        ('cancel', <String, Object?>{}),
        ('add', {'by': 1}),
      ]),
    ]);
    await expectLater(
      AgentRuntime.run<_Tally>(
        provider: provider,
        messages: messages,
        tools: [_Add(), _Cancels()],
        context: _Tally(),
        maxRounds: 3,
        isDone: () => false,
      ),
      throwsA(isA<AiCancelled>()),
    );
    final results = messages.whereType<ToolResultMessage>().toList();
    expect(results.map((r) => r.toolCallId), ['c0', 'c1']);
    expect(
      results.every((r) => r.content == AgentRuntime.notRunResult),
      isTrue,
    );
  });

  test('rounds of nothing but failed calls end the run', () async {
    final provider = ScriptedChatProvider([
      (_) => toolTurn([('multiply', <String, Object?>{})]),
    ]);

    final result = await _run(provider, _Tally(), isDone: () => false);

    expect(result.outcome, AgentOutcome.erratic);
    expect(provider.calls, AgentRuntime.maxErraticRounds);
  });

  test('cut-off tool calls end as truncated, not erratic', () async {
    final provider = ScriptedChatProvider([
      (_) => const ChatResult(
        toolCalls: [ToolCall(id: 'c0', name: 'add', arguments: '{"by": ')],
        finishReason: 'length',
      ),
    ]);

    final result = await _run(provider, _Tally(), isDone: () => false);

    expect(result.outcome, AgentOutcome.truncated);
    expect(provider.calls, AgentRuntime.maxTruncatedRounds);
  });

  test('a reply cut off without a tool call is retried, not nudged', () async {
    var nudged = 0;
    final provider = ScriptedChatProvider([
      (_) => const ChatResult(text: 'Let me think', finishReason: 'length'),
    ]);

    final result = await _run(
      provider,
      _Tally(),
      nudge: () {
        nudged++;
        return 'keep going';
      },
    );

    expect(result.outcome, AgentOutcome.truncated);
    expect(nudged, 0);
    expect(provider.calls, AgentRuntime.maxTruncatedRounds);
  });

  test('cut-off replies that are not in a row do not end the run', () async {
    const cut = ChatResult(text: 'Let me think', finishReason: 'length');
    const whole = ChatResult(text: 'Done, I think.');
    final provider = ScriptedChatProvider([
      (_) => cut,
      (_) => whole,
      (_) => cut,
      (_) => whole,
    ]);

    final result = await _run(provider, _Tally(), nudge: () => 'keep going');

    expect(result.outcome, isNot(AgentOutcome.truncated));
  });

  test('the truncation message names the current output cap', () {
    expect(AgentRuntime.truncatedMessage(4096), contains('4096'));
    expect(AgentRuntime.truncatedMessage(null), isNot(contains('null')));
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

    test('counts what an assistant turn sends back', () {
      final call = [const ToolCall(id: 'c0', name: 'add', arguments: '{}')];
      final plain = AgentRuntime.estimate(AssistantMessage(toolCalls: call));
      final withReasoning = AgentRuntime.estimate(
        AssistantMessage(
          toolCalls: call,
          reasoning: (
            field: 'reasoning_content',
            text: 'x' * 4000,
            encrypted: null,
          ),
        ),
      );
      final withParts = AgentRuntime.estimate(
        AssistantMessage(
          toolCalls: call,
          raw: ProviderTurn(
            protocol: AiProviderType.googleGenAi,
            model: 'm',
            parts: [
              {
                'functionCall': {'name': 'add', 'args': <String, Object?>{}},
                'thoughtSignature': 'y' * 4000,
              },
            ],
          ),
        ),
      );
      expect(withReasoning, greaterThan(plain + 500));
      // The signature is opaque: it is sent, but not counted as text.
      expect(withParts, lessThan(plain + 100));
    });

    test('an image is counted by what it costs, not its bytes', () {
      final text = AgentRuntime.estimate(const UserMessage('look'));
      final withImages = AgentRuntime.estimate(
        UserMessage(
          'look',
          images: [
            for (var i = 0; i < 3; i++) ImagePart(bytes: Uint8List(100000)),
          ],
        ),
      );
      expect(withImages - text, 3 * AgentRuntime.imageTokens);
    });

    test('leaves a history that fits alone', () {
      final messages = _seed();
      expect(AgentRuntime.trimHistory(messages, 4096), 0);
    });

    test('the tool schemas come off the ceiling too', () {
      List<ChatMessage> history() => [
        const SystemMessage('system'),
        const UserMessage('go'),
        const AssistantMessage(
          toolCalls: [ToolCall(id: 'c0', name: 'add', arguments: '{}')],
        ),
        ToolResultMessage(toolCallId: 'c0', name: 'add', content: 'x' * 2400),
      ];

      // The same history fits when only the messages are counted and does not
      // once the request's own tool schemas are charged against the window.
      expect(AgentRuntime.trimHistory(history(), 1600, reserve: 100), 0);
      expect(
        AgentRuntime.trimHistory(history(), 1600, reserve: 100, overhead: 600),
        1,
      );
    });
  });

  group('one-shot reminders', () {
    test('a reminder is retracted once it has been sent', () async {
      final provider = ScriptedChatProvider([
        (_) => textTurn('I think I am done.'),
        (_) => toolTurn([
          ('add', {'by': 2}),
        ]),
      ]);
      final messages = _seed();
      final seeded = messages.length;

      final result = await AgentRuntime.run<_Tally>(
        provider: provider,
        messages: messages,
        tools: [_Add()],
        context: _Tally(),
        maxRounds: 6,
        isDone: () => provider.calls > 1,
        nudge: () => 'Still undecided: g3, g7. Call add.',
      );

      expect(result.outcome, AgentOutcome.completed);
      // The reminder was in the history for exactly the request it was
      // written for.
      expect(
        (provider.seen[1].last as UserMessage).content,
        'Still undecided: g3, g7. Call add.',
      );
      // …and afterwards the whole exchange is gone. A stale reminder left in
      // the history stands as a permanent instruction — and this one carries
      // state that is wrong by the next round — while the model's "I am done"
      // turn would leave two assistant turns in a row once it resumed calling
      // tools, which Gemini rejects. What is left is the seed plus the real
      // round: one assistant turn and its tool result.
      expect(messages, hasLength(seeded + 2));
      expect(
        messages.any(
          (m) => m is UserMessage && m.content.contains('Still undecided'),
        ),
        isFalse,
      );
      expect(
        messages.any(
          (m) => m is AssistantMessage && m.content == 'I think I am done.',
        ),
        isFalse,
      );
      expect(messages[seeded], isA<AssistantMessage>());
      expect(messages[seeded + 1], isA<ToolResultMessage>());
    });

    test('two reminders never pile up', () async {
      final provider = ScriptedChatProvider([(_) => textTurn('Done!')]);

      await _run(
        provider,
        _Tally(),
        isDone: () => false,
        nudge: () => 'Call add.',
      );

      expect(provider.calls, 3);
      for (final history in provider.seen) {
        expect(
          history.where((m) => m is UserMessage && m.content == 'Call add.'),
          hasLength(lessThanOrEqualTo(1)),
        );
      }
    });
  });
}
