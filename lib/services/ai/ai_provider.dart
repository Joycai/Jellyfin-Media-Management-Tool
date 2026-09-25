/// Transport-level abstraction over an LLM endpoint.
///
/// Implementations only handle HTTP and provider-specific request/response
/// shapes; they return the model's text, tool calls and token usage. Turning
/// that into domain results happens one layer up, so the providers stay free
/// of any domain knowledge.
library;

import 'ai_cancel_token.dart';
import 'chat.dart';
import 'learned_behaviour.dart';
import 'model_limits.dart';
import 'sampling_presets.dart';

export 'chat.dart';
export 'model_limits.dart' show ModelLimits;
export 'sampling_presets.dart'
    show
        ResolvedSampling,
        SamplingPreset,
        SamplingPresets,
        SamplingValues,
        ThinkingControl;

/// Identifies which wire protocol a provider speaks — the four protocol
/// families. A vendor is never a type here: it is a row of data in
/// `PlatformProfiles`.
enum AiProviderType {
  /// ① OpenAI-compatible `/chat/completions` (OpenAI, Azure, LM Studio,
  /// Ollama, llama.cpp, vLLM, …).
  openAi,

  /// ③ Google Generative Language API (`:streamGenerateContent`).
  googleGenAi,

  /// ④ Anthropic Messages (`/v1/messages`).
  anthropic,

  /// ② OpenAI Responses (`/v1/responses`).
  openAiResponses,
}

extension AiProviderTypeX on AiProviderType {
  String get id => switch (this) {
    AiProviderType.openAi => 'openai',
    AiProviderType.googleGenAi => 'google',
    AiProviderType.anthropic => 'anthropic',
    AiProviderType.openAiResponses => 'responses',
  };

  /// Whether a profile is unusable without an API key.
  ///
  /// Google's and Anthropic's APIs reject every keyless request. An
  /// OpenAI-compatible server often wants none at all — LM Studio, Ollama,
  /// llama.cpp and vLLM run without authentication by default — and requiring
  /// one there made users invent a key just to get past the form.
  bool get requiresApiKey =>
      this == AiProviderType.googleGenAi || this == AiProviderType.anthropic;

  /// Reads a stored id; an unknown one is the OpenAI-compatible protocol, as
  /// every profile before protocols had ids.
  static AiProviderType fromId(String? id) =>
      tryFromId(id) ?? AiProviderType.openAi;

  static AiProviderType? tryFromId(String? id) {
    for (final type in AiProviderType.values) {
      if (type.id == id) return type;
    }
    return null;
  }
}

/// The software behind an OpenAI-compatible endpoint. They agree on the
/// request shape and disagree on nearly everything around it: which sampling
/// fields they honour, and how reasoning is turned off.
enum ServerKind { lmStudio, ollama, llamaCpp, vllm, unknown }

/// Result of a single completion call.
class AiResponse {
  final String text;
  final int promptTokens;
  final int completionTokens;

  /// Why generation stopped, as the server put it (`stop`, `length`,
  /// `MAX_TOKENS`, …). Null when it did not say.
  final String? finishReason;

  /// The reply carried reasoning — reasoning deltas, reasoning tokens in the
  /// usage, or a leading think block.
  final bool reasoned;

  /// Reasoning ran although this request asked for none, and the provider has
  /// another way of asking that the next request will use. Lets a caller that
  /// can afford a retry, such as the connection test, find out now.
  final bool thinkingOffPending;

  const AiResponse({
    required this.text,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
    this.reasoned = false,
    this.thinkingOffPending = false,
  });

  int get totalTokens => promptTokens + completionTokens;

  /// True when the server cut the reply off at its output limit.
  bool get truncated => FinishReasons.isTruncation(finishReason);

  factory AiResponse.fromChat(ChatResult result) => AiResponse(
    text: result.text,
    promptTokens: result.promptTokens,
    completionTokens: result.completionTokens,
    finishReason: result.finishReason,
    reasoned: result.reasoned,
    thinkingOffPending: result.thinkingOffPending,
  );
}

/// Raised when a provider call fails. Carries a human-readable message that is
/// safe to surface in the UI.
class AiException implements Exception {
  final String message;
  const AiException(this.message);

  @override
  String toString() => message;
}

/// An [AiException] that settles nothing about the model: the request did not
/// complete, or the server failed it for a reason of its own (a bad or
/// unauthorised key, a rate limit, an empty balance, an upstream crash,
/// Gemini's catch-all `OTHER`) — see `AiHttp.statusError`.
///
/// The distinction is what keeps a network blip from being recorded as a fact
/// about a model — see [AiConnectionCheck.probeTools].
class AiNetworkException extends AiException {
  const AiNetworkException(super.message);
}

/// Whether a model called a tool when asked to, and which provider, endpoint
/// and model that was measured against.
class ToolSupport {
  final String fingerprint;
  final bool supported;

  const ToolSupport({required this.fingerprint, required this.supported});

  Map<String, dynamic> toJson() => {'for': fingerprint, 'supported': supported};

  static ToolSupport? fromJson(Object? json) {
    if (json is! Map) return null;
    final fingerprint = json['for'];
    final supported = json['supported'];
    return fingerprint is String && supported is bool
        ? ToolSupport(fingerprint: fingerprint, supported: supported)
        : null;
  }
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

  /// Sampling overrides. Null follows the model family's preset — see
  /// [sampling].
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? minP;
  final double? presencePenalty;
  final double? repeatPenalty;

  /// Whether reasoning should run. Off by default: on a small local model it
  /// multiplies the time a task takes, and it is where the looping comes
  /// from. A family that can only reason ignores it.
  final bool thinkingEnabled;

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

  /// The last tool-calling check; read it through [supportsTools], which
  /// ignores a result measured against a different endpoint or model.
  final ToolSupport? toolSupport;

  /// The platform profile the channel belongs to (`PlatformProfiles`), which
  /// decides the private fields a request may carry. Null is "custom":
  /// protocol-standard fields only, or what the host implies.
  final String? platform;

  /// The user allows images, and video frames, to reach this model.
  final bool imageInput;
  final bool videoInput;

  const AiConfig({
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
    this.toolSupport,
    this.platform,
    this.imageInput = false,
    this.videoInput = false,
  });

  /// Endpoint and model are always needed; a key only where the protocol
  /// demands one — see [AiProviderTypeX.requiresApiKey].
  bool get isComplete =>
      endpoint.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      (!provider.requiresApiKey || apiKey.trim().isNotEmpty);

  /// What a tool-support result is measured against. Changing any part of it
  /// makes an earlier result stale.
  String get toolFingerprint =>
      '${provider.id}|${endpoint.trim()}|${model.trim()}';

  /// Whether this model calls tools: true or false once checked, null when it
  /// never was for this endpoint and model. Every agent task needs true —
  /// there is no single-shot fallback.
  bool? get supportsTools {
    final support = toolSupport;
    return support != null && support.fingerprint == toolFingerprint
        ? support.supported
        : null;
  }

  AiConfig withToolSupport(bool supported) => AiConfig(
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
    toolSupport: ToolSupport(
      fingerprint: toolFingerprint,
      supported: supported,
    ),
    platform: platform,
    imageInput: imageInput,
    videoInput: videoInput,
  );

  SamplingValues get samplingOverrides => SamplingValues(
    temperature: temperature,
    topP: topP,
    topK: topK,
    minP: minP,
    presencePenalty: presencePenalty,
    repeatPenalty: repeatPenalty,
  );

  /// What a request to this model sends: overrides over the family preset.
  ResolvedSampling get sampling => ResolvedSampling.of(
    model: model,
    thinkingRequested: thinkingEnabled,
    overrides: samplingOverrides,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider.id,
    'endpoint': endpoint,
    'api_key': apiKey,
    'model': model,
    // A new key rather than `temperature`: see [legacyTemperature].
    'temperature_override': temperature,
    'top_p': topP,
    'top_k': topK,
    'min_p': minP,
    'presence_penalty': presencePenalty,
    'repeat_penalty': repeatPenalty,
    'thinking_enabled': thinkingEnabled,
    'context_window': contextWindow,
    'max_output_tokens': maxOutputTokens,
    'tool_support': toolSupport?.toJson(),
    'platform': ?platform,
    if (imageInput) 'image_input': true,
    if (videoInput) 'video_input': true,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    provider: AiProviderTypeX.fromId(json['provider'] as String?),
    endpoint: (json['endpoint'] as String?) ?? '',
    apiKey: (json['api_key'] as String?) ?? '',
    model: (json['model'] as String?) ?? '',
    temperature: json.containsKey('temperature_override')
        ? decimal(json['temperature_override'])
        : legacyTemperature(json['temperature']),
    topP: decimal(json['top_p']),
    topK: tokenCount(json['top_k']),
    minP: decimal(json['min_p']),
    presencePenalty: decimal(json['presence_penalty']),
    repeatPenalty: decimal(json['repeat_penalty']),
    thinkingEnabled: json['thinking_enabled'] == true,
    contextWindow: tokenCount(json['context_window']),
    maxOutputTokens: tokenCount(json['max_output_tokens']),
    toolSupport: ToolSupport.fromJson(json['tool_support']),
    platform: json['platform'] is String ? json['platform'] as String : null,
    imageInput: json['image_input'] == true,
    videoInput: json['video_input'] == true,
  );

  /// Reads a temperature saved before presets existed.
  ///
  /// Every profile carried one, and `0.2` was the fixed default rather than a
  /// choice, so reading it as "unset" is what lets the model's recommended
  /// value apply. Any other value was typed by the user and is kept. This
  /// version saves under `temperature_override` instead, so a user who now
  /// picks 0.2 on purpose keeps it.
  static double? legacyTemperature(Object? value) {
    final t = decimal(value);
    return t == ResolvedSampling.legacyTemperature ? null : t;
  }

  /// Reads a non-negative decimal from JSON or a text field; anything else
  /// means "unset".
  static double? decimal(Object? value) {
    final d = switch (value) {
      num v => v.toDouble(),
      String v => double.tryParse(v.trim()),
      _ => null,
    };
    return d != null && d.isFinite && d >= 0 ? d : null;
  }

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
  /// Defaults for a new channel come from its platform profile, not from
  /// here.
  static const empty = AiConfig(
    provider: AiProviderType.openAi,
    endpoint: '',
    apiKey: '',
    model: '',
  );
}

/// What a provider would send for a request, for the settings preview:
/// built by the same code as the real request, with the key masked.
class RequestPreview {
  final Uri url;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  const RequestPreview({
    required this.url,
    required this.headers,
    required this.body,
  });

  /// `sk-…3f9a`: enough to tell two keys apart, not enough to use one.
  static String mask(String key) {
    final k = key.trim();
    if (k.length <= 8) return '…';
    return '${k.substring(0, 3)}…${k.substring(k.length - 4)}';
  }
}

/// A provider turns prompts into model text and tool calls.
abstract class AiProvider {
  AiConfig get config;

  /// Performs one JSON-mode completion. Throws [AiException] on failure, or
  /// [AiCancelled] when [cancelToken] is cancelled while the call is in flight.
  Future<AiResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    AiCancelToken? cancelToken,
  });

  /// One turn of a tool-calling conversation: sends [messages] with [tools]
  /// on offer and returns the reply — text, tool calls, or both. No JSON mode:
  /// forced JSON and tools exclude each other on most servers. Throws like
  /// [complete].
  Future<ChatResult> chat({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    AiCancelToken? cancelToken,
  });

  /// What the server reports about the model's context window and output cap,
  /// without generating anything. Best-effort: never throws, and returns
  /// [ModelLimits.unknown] when nothing answered.
  Future<ModelLimits> detectLimits();

  /// Which software serves the endpoint. Best-effort: never throws.
  Future<ServerKind> detectServerKind();

  /// Drops what this provider learned about its route — refused fields, the
  /// JSON mode, the way reasoning was turned off — so the next request finds
  /// out again. The connection test calls it first.
  void forgetLearned();

  /// What this provider has learned about its route so far.
  LearnedBehaviour get learned;

  /// The request a [chat] turn would send, without sending anything. Null
  /// where this build has no adapter for the protocol.
  Future<RequestPreview?> previewRequest({
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
  });
}
