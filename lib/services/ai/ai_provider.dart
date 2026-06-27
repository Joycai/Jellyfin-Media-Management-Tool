/// Transport-level abstraction over an LLM endpoint.
///
/// Implementations only handle HTTP and provider-specific request/response
/// shapes; they return the raw model text plus token usage. Parsing the text
/// into an [OrganizePlan] happens one layer up in `AiService`, so the providers
/// stay free of any domain knowledge.
library;

/// Identifies which wire protocol a provider speaks.
enum AiProviderType {
  /// OpenAI-compatible `/chat/completions` (OpenAI, Azure, LocalAI, Ollama, …).
  openAi,

  /// Google Generative Language API (`:generateContent`).
  googleGenAi,
}

extension AiProviderTypeX on AiProviderType {
  String get id => switch (this) {
        AiProviderType.openAi => 'openai',
        AiProviderType.googleGenAi => 'google',
      };

  static AiProviderType fromId(String? id) => switch (id) {
        'google' => AiProviderType.googleGenAi,
        _ => AiProviderType.openAi,
      };
}

/// Result of a single completion call.
class AiResponse {
  final String text;
  final int promptTokens;
  final int completionTokens;

  const AiResponse({
    required this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  int get totalTokens => promptTokens + completionTokens;
}

/// Raised when a provider call fails. Carries a human-readable message that is
/// safe to surface in the UI.
class AiException implements Exception {
  final String message;
  const AiException(this.message);

  @override
  String toString() => message;
}

/// Connection details shared by every provider.
class AiConfig {
  final AiProviderType provider;

  /// Base URL / endpoint. For OpenAI this is the API root (e.g.
  /// `https://api.openai.com/v1`); for Google it is the API root
  /// (e.g. `https://generativelanguage.googleapis.com`).
  final String endpoint;
  final String apiKey;
  final String model;
  final double temperature;

  const AiConfig({
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

  AiConfig copyWith({
    AiProviderType? provider,
    String? endpoint,
    String? apiKey,
    String? model,
    double? temperature,
  }) =>
      AiConfig(
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider.id,
        'endpoint': endpoint,
        'api_key': apiKey,
        'model': model,
        'temperature': temperature,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        provider: AiProviderTypeX.fromId(json['provider'] as String?),
        endpoint: (json['endpoint'] as String?) ?? '',
        apiKey: (json['api_key'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      );

  static const empty = AiConfig(
    provider: AiProviderType.openAi,
    endpoint: 'https://api.openai.com/v1',
    apiKey: '',
    model: 'gpt-4o-mini',
  );
}

/// A provider turns a (system, user) prompt pair into model text.
abstract class AiProvider {
  AiConfig get config;

  /// Performs one JSON-mode completion. Throws [AiException] on failure.
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
  });

  /// Lightweight connectivity/credential check. Returns true on success.
  Future<bool> testConnection();
}
