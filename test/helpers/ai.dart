import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';

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
  Future<ModelLimits> detectLimits() async => ModelLimits.unknown;
}
