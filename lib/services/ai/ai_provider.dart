/// Transport-level abstraction over an LLM endpoint.
///
/// Implementations only handle HTTP and provider-specific request/response
/// shapes; they return the raw model text plus token usage. Parsing the text
/// into an [OrganizePlan] happens one layer up in `AiService`, so the providers
/// stay free of any domain knowledge.
library;

import 'ai_cancel_token.dart';
import 'model_limits.dart';

export 'model_limits.dart' show ModelLimits;

/// Identifies which wire protocol a provider speaks.
enum AiProviderType {
  /// OpenAI-compatible `/chat/completions` (OpenAI, Azure, LM Studio, Ollama,
  /// llama.cpp, vLLM, …).
  openAi,

  /// Google Generative Language API (`:generateContent`).
  googleGenAi,
}

extension AiProviderTypeX on AiProviderType {
  String get id => switch (this) {
    AiProviderType.openAi => 'openai',
    AiProviderType.googleGenAi => 'google',
  };

  /// Whether a profile is unusable without an API key.
  ///
  /// Google's API rejects every keyless request. An OpenAI-compatible server
  /// often wants none at all — LM Studio, Ollama, llama.cpp and vLLM run
  /// without authentication by default — and requiring one there made users
  /// invent a key just to get past the form.
  bool get requiresApiKey => this == AiProviderType.googleGenAi;

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

  /// Why generation stopped, as the server put it (`stop`, `length`,
  /// `MAX_TOKENS`, …). Null when it did not say.
  final String? finishReason;

  const AiResponse({
    required this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
  });

  int get totalTokens => promptTokens + completionTokens;

  /// True when the server cut the reply off at its output limit.
  bool get truncated => switch (finishReason?.toLowerCase()) {
    'length' || 'max_tokens' => true,
    _ => false,
  };
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

  /// Tokens the model is served with, or null when unknown.
  ///
  /// A budget, not a server setting. OpenAI-compatible servers fix the context
  /// when the model is loaded — LM Studio's slider, Ollama's `num_ctx`,
  /// llama.cpp's `-c` — and none accept it per request, so the app cannot
  /// change it. What it can do is stop sending more than fits: a local server
  /// does not reject an oversized prompt, it drops the front of it, system
  /// prompt first, and the model answers confidently without its
  /// instructions. Null sends every prompt at its natural size, as before.
  final int? contextWindow;

  /// Cap on generated tokens, sent as `max_tokens` (or
  /// `max_completion_tokens`) / `maxOutputTokens`. Null leaves the server's
  /// default.
  final int? maxOutputTokens;

  const AiConfig({
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.temperature = 0.2,
    this.contextWindow,
    this.maxOutputTokens,
  });

  /// Endpoint and model are always needed; a key only where the protocol
  /// demands one — see [AiProviderTypeX.requiresApiKey].
  bool get isComplete =>
      endpoint.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      (!provider.requiresApiKey || apiKey.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
    'provider': provider.id,
    'endpoint': endpoint,
    'api_key': apiKey,
    'model': model,
    'temperature': temperature,
    'context_window': contextWindow,
    'max_output_tokens': maxOutputTokens,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    provider: AiProviderTypeX.fromId(json['provider'] as String?),
    endpoint: (json['endpoint'] as String?) ?? '',
    apiKey: (json['api_key'] as String?) ?? '',
    model: (json['model'] as String?) ?? '',
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
    contextWindow: tokenCount(json['context_window']),
    maxOutputTokens: tokenCount(json['max_output_tokens']),
  );

  /// Reads a token count from JSON or a text field. Anything that is not a
  /// positive integer means "unset" — a stray `0` must not become zero room.
  static int? tokenCount(Object? value) {
    final n = switch (value) {
      num v => v.toInt(),
      String v => int.tryParse(v.trim()),
      _ => null,
    };
    return n != null && n > 0 ? n : null;
  }

  /// Truly empty sentinel — every string is blank so [isComplete] is false and
  /// nothing accidentally hits a real endpoint before the user configures one.
  /// Editor-side defaults (the `api.openai.com` URL and `gpt-4o-mini` model)
  /// live in [AiServiceProfile.create], not here.
  static const empty = AiConfig(
    provider: AiProviderType.openAi,
    endpoint: '',
    apiKey: '',
    model: '',
  );
}

/// A provider turns a (system, user) prompt pair into model text.
abstract class AiProvider {
  AiConfig get config;

  /// Performs one JSON-mode completion. Throws [AiException] on failure, or
  /// [AiCancelled] when [cancelToken] is cancelled while the call is in flight.
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  });

  /// What the server reports about the model's context window and output cap,
  /// without generating anything. Best-effort: never throws, and returns
  /// [ModelLimits.unknown] when nothing answered.
  Future<ModelLimits> detectLimits();
}
