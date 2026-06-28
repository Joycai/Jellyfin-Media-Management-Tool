import '../services/ai/ai_provider.dart';
import '../utils/ids.dart';

/// A single configured AI endpoint the user can manage. One profile is the
/// "active" one that drives organization; the rest are kept on standby.
class AiServiceProfile {
  final String id;
  final String name;
  final AiProviderType provider;
  final String endpoint;
  final String apiKey;
  final String model;
  final double temperature;

  const AiServiceProfile({
    required this.id,
    required this.name,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.temperature = 0.2,
  });

  bool get isComplete =>
      endpoint.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  /// Runtime config consumed by the providers / [AiService].
  AiConfig toAiConfig() => AiConfig(
        provider: provider,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
      );

  AiServiceProfile copyWith({
    String? name,
    AiProviderType? provider,
    String? endpoint,
    String? apiKey,
    String? model,
    double? temperature,
  }) =>
      AiServiceProfile(
        id: id,
        name: name ?? this.name,
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider.id,
        'endpoint': endpoint,
        'api_key': apiKey,
        'model': model,
        'temperature': temperature,
      };

  /// Reads a profile from JSON. Older configs may carry a `rate_limit` field
  /// from a previous schema — it's silently ignored here.
  factory AiServiceProfile.fromJson(Map<String, dynamic> json) => AiServiceProfile(
        id: (json['id'] as String?) ?? newId(),
        name: (json['name'] as String?) ?? 'AI Service',
        provider: AiProviderTypeX.fromId(json['provider'] as String?),
        endpoint: (json['endpoint'] as String?) ?? '',
        apiKey: (json['api_key'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      );

  /// A fresh, empty profile with sensible defaults for [provider].
  factory AiServiceProfile.create({AiProviderType provider = AiProviderType.openAi, required String name}) =>
      AiServiceProfile(
        id: newId(),
        name: name,
        provider: provider,
        endpoint: provider == AiProviderType.openAi
            ? 'https://api.openai.com/v1'
            : 'https://generativelanguage.googleapis.com',
        apiKey: '',
        model: provider == AiProviderType.openAi ? 'gpt-4o-mini' : 'gemini-2.0-flash',
      );
}
