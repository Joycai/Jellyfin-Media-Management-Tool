import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/connection_check.dart';

import '../../helpers/ai.dart';

void main() {
  group('AiConfig.isComplete', () {
    const local = AiConfig(
      provider: AiProviderType.openAi,
      endpoint: 'http://localhost:1234/v1',
      apiKey: '',
      model: 'qwen/qwen3-8b',
    );

    test('an OpenAI-compatible server needs no key', () {
      expect(local.isComplete, isTrue);
    });

    test('Google does', () {
      const google = AiConfig(
        provider: AiProviderType.googleGenAi,
        endpoint: 'https://generativelanguage.googleapis.com',
        apiKey: '',
        model: 'gemini-2.0-flash',
      );
      expect(google.isComplete, isFalse);
    });

    test('token counts survive a round trip; junk means unset', () {
      const budgeted = AiConfig(
        provider: AiProviderType.openAi,
        endpoint: 'http://localhost:1234/v1',
        apiKey: '',
        model: 'm',
        contextWindow: 8192,
        maxOutputTokens: 2048,
      );
      final restored = AiConfig.fromJson(budgeted.toJson());
      expect(restored.contextWindow, 8192);
      expect(restored.maxOutputTokens, 2048);

      expect(AiConfig.tokenCount(' 4096 '), 4096);
      expect(AiConfig.tokenCount('0'), isNull);
      expect(AiConfig.tokenCount(-1), isNull);
      expect(AiConfig.tokenCount('abc'), isNull);
      expect(AiConfig.tokenCount(null), isNull);
    });
  });

  group('AiConnectionCheck', () {
    test('sends a real completion and reports the greeting', () async {
      final provider = ScriptedProvider(['{"reply": "Hello there!"}']);

      final result = await AiConnectionCheck.run(provider);

      // The greeting, then the tool check — asked twice, since this scripted
      // model only ever answers in prose.
      expect(provider.calls, 3);
      expect(result.supportsTools, isFalse);
      expect(result.reply, 'Hello there!');
      expect(result.truncated, isFalse);
      expect(result.limits.isEmpty, isTrue);
    });

    test('a model that ignores the format still counts as answering', () {
      expect(
        AiConnectionCheck.replyText('```json\n{"reply": "Hi"}\n```'),
        'Hi',
      );
      expect(AiConnectionCheck.replyText('  Hello!  '), 'Hello!');
      expect(AiConnectionCheck.replyText(''), '');
    });
  });
}
