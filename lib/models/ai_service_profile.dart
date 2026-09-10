import '../services/ai/ai_provider.dart';
import '../utils/ids.dart';

/// A single configured AI endpoint the user can manage. One profile is the
/// "active" one that drives organization; the rest are kept on standby.
///
/// Mirrors [AiConfig] field for field, and serializes through it, so the two
/// can never disagree about a key or a migration.
class AiServiceProfile {
  final String id;
  final String name;
  final AiProviderType provider;
  final String endpoint;
  final String apiKey;
  final String model;

  /// Sampling overrides; see [AiConfig.temperature] and its siblings.
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? minP;
  final double? presencePenalty;
  final double? repeatPenalty;

  /// See [AiConfig.thinkingEnabled].
  final bool thinkingEnabled;

  /// See [AiConfig.contextWindow].
  final int? contextWindow;

  /// See [AiConfig.maxOutputTokens].
  final int? maxOutputTokens;

  const AiServiceProfile({
    required this.id,
    required this.name,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.temperature,
    this.topP,
    this.topK,
    this.minP,
    this.presencePenalty,
    this.repeatPenalty,
    this.thinkingEnabled = false,
    this.contextWindow,
    this.maxOutputTokens,
  });

  factory AiServiceProfile.fromConfig({
    required String id,
    required String name,
    required AiConfig config,
  }) => AiServiceProfile(
    id: id,
    name: name,
    provider: config.provider,
    endpoint: config.endpoint,
    apiKey: config.apiKey,
    model: config.model,
    temperature: config.temperature,
    topP: config.topP,
    topK: config.topK,
    minP: config.minP,
    presencePenalty: config.presencePenalty,
    repeatPenalty: config.repeatPenalty,
    thinkingEnabled: config.thinkingEnabled,
    contextWindow: config.contextWindow,
    maxOutputTokens: config.maxOutputTokens,
  );

  /// Delegates to [AiConfig.isComplete] so the settings badge and the runtime
  /// can never disagree about whether a key is required.
  bool get isComplete => toAiConfig().isComplete;

  /// Runtime config consumed by the providers / [AiService].
  AiConfig toAiConfig() => AiConfig(
    provider: provider,
    endpoint: endpoint,
    apiKey: apiKey,
    model: model,
    temperature: temperature,
    topP: topP,
    topK: topK,
    minP: minP,
    presencePenalty: presencePenalty,
    repeatPenalty: repeatPenalty,
    thinkingEnabled: thinkingEnabled,
    contextWindow: contextWindow,
    maxOutputTokens: maxOutputTokens,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    ...toAiConfig().toJson(),
  };

  /// Reads a profile from JSON. Older configs may carry a `rate_limit` field
  /// from a previous schema — it's silently ignored here.
  factory AiServiceProfile.fromJson(Map<String, dynamic> json) =>
      AiServiceProfile.fromConfig(
        id: (json['id'] as String?) ?? newId(),
        name: (json['name'] as String?) ?? 'AI Service',
        config: AiConfig.fromJson(json),
      );

  /// A fresh, empty profile with sensible defaults for [provider].
  factory AiServiceProfile.create({
    AiProviderType provider = AiProviderType.openAi,
    required String name,
  }) => AiServiceProfile(
    id: newId(),
    name: name,
    provider: provider,
    endpoint: provider == AiProviderType.openAi
        ? 'https://api.openai.com/v1'
        : 'https://generativelanguage.googleapis.com',
    apiKey: '',
    model: provider == AiProviderType.openAi
        ? 'gpt-4o-mini'
        : 'gemini-2.0-flash',
  );
}
