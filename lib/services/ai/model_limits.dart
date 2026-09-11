/// What a server says about a model's context window and output cap.
///
/// No compatible API has a standard field for this, so each local server is
/// asked in its own dialect. The distinction that matters is between the size
/// a model is *loaded* with and the size it *supports*: Ollama and LM Studio
/// load a fraction of the model's maximum by default, and budgeting a prompt
/// against the maximum overflows the real window — which these servers handle
/// by silently dropping the front of the prompt, not by returning an error.
library;

class ModelLimits {
  final int? contextWindow;
  final int? maxOutputTokens;

  /// Which server answered, for the UI. A product name, so not localised.
  final String? source;

  /// [contextWindow] is what the model supports rather than what it was
  /// loaded with, so the real window may well be smaller.
  final bool isModelMaximum;

  const ModelLimits({
    this.contextWindow,
    this.maxOutputTokens,
    this.source,
    this.isModelMaximum = false,
  });

  static const unknown = ModelLimits();

  bool get isEmpty => contextWindow == null && maxOutputTokens == null;

  /// The first answer in [candidates] (most authoritative first), preferring
  /// any loaded size over every model maximum.
  static ModelLimits pick(Iterable<ModelLimits?> candidates) {
    final found = [
      for (final c in candidates)
        if (c != null && !c.isEmpty) c,
    ];
    if (found.isEmpty) return unknown;
    return found.firstWhere(
      (c) => !c.isModelMaximum,
      orElse: () => found.first,
    );
  }

  /// llama.cpp `GET /props`: `default_generation_settings.n_ctx` is the `-c`
  /// the server was started with — the most exact number any of them gives.
  static ModelLimits? fromLlamaCppProps(Object? json) {
    if (json is! Map) return null;
    final settings = json['default_generation_settings'];
    final ctx =
        _positive(settings is Map ? settings['n_ctx'] : null) ??
        _positive(json['n_ctx']);
    return ctx == null
        ? null
        : ModelLimits(contextWindow: ctx, source: 'llama.cpp');
  }

  /// LM Studio `GET /api/v0/models`: `loaded_context_length` for a model in
  /// memory, `max_context_length` for what it could be loaded with.
  static ModelLimits? fromLmStudioModels(Object? json, String model) {
    final entry = _entry(json, 'data', model, const ['id']);
    if (entry == null) return null;
    final loaded = _positive(entry['loaded_context_length']);
    if (loaded != null) {
      return ModelLimits(contextWindow: loaded, source: 'LM Studio');
    }
    final max = _positive(entry['max_context_length']);
    return max == null
        ? null
        : ModelLimits(
            contextWindow: max,
            source: 'LM Studio',
            isModelMaximum: true,
          );
  }

  /// Ollama `GET /api/ps`: newer builds report a running model's
  /// `context_length` — the `num_ctx` it is actually serving.
  static ModelLimits? fromOllamaPs(Object? json, String model) {
    final entry = _entry(json, 'models', model, const ['name', 'model']);
    final ctx = _positive(entry?['context_length']);
    return ctx == null
        ? null
        : ModelLimits(contextWindow: ctx, source: 'Ollama');
  }

  /// Ollama `POST /api/show`: a `num_ctx` line in `parameters` when the
  /// Modelfile sets one, otherwise `<arch>.context_length` from `model_info` —
  /// the model's maximum, which Ollama does not load by default.
  /// The `num_ctx` line in an Ollama Modelfile's `parameters` block.
  static final _numCtx = RegExp(r'^\s*num_ctx\s+(\d+)', multiLine: true);

  static ModelLimits? fromOllamaShow(Object? json) {
    if (json is! Map) return null;
    final parameters = json['parameters'];
    if (parameters is String) {
      final match = _numCtx.firstMatch(parameters);
      final ctx = _positive(match?.group(1));
      if (ctx != null) return ModelLimits(contextWindow: ctx, source: 'Ollama');
    }
    final info = json['model_info'];
    if (info is Map) {
      for (final entry in info.entries) {
        final key = entry.key;
        if (key is! String || !key.endsWith('.context_length')) continue;
        final ctx = _positive(entry.value);
        if (ctx != null) {
          return ModelLimits(
            contextWindow: ctx,
            source: 'Ollama',
            isModelMaximum: true,
          );
        }
      }
    }
    return null;
  }

  /// `GET /v1/models`: vLLM's `max_model_len` is its launch argument, so the
  /// real window; OpenRouter and some gateways add `context_length`, and
  /// OpenRouter an output cap under `top_provider`.
  static ModelLimits? fromOpenAiModels(Object? json, String model) {
    final entry = _entry(json, 'data', model, const ['id']);
    if (entry == null) return null;
    final vllm = _positive(entry['max_model_len']);
    if (vllm != null) return ModelLimits(contextWindow: vllm, source: 'vLLM');
    final top = entry['top_provider'];
    final ctx = _positive(entry['context_length']);
    final out = top is Map ? _positive(top['max_completion_tokens']) : null;
    if (ctx == null && out == null) return null;
    return ModelLimits(
      contextWindow: ctx,
      maxOutputTokens: out,
      source: '/v1/models',
    );
  }

  /// Google `GET models/{model}`: the limits the API itself enforces.
  static ModelLimits? fromGoogleModel(Object? json) {
    if (json is! Map) return null;
    final ctx = _positive(json['inputTokenLimit']);
    final out = _positive(json['outputTokenLimit']);
    if (ctx == null && out == null) return null;
    return ModelLimits(
      contextWindow: ctx,
      maxOutputTokens: out,
      source: 'Google',
    );
  }

  static Map<dynamic, dynamic>? _entry(
    Object? json,
    String listKey,
    String model,
    List<String> idKeys,
  ) {
    if (json is! Map) return null;
    final list = json[listKey];
    if (list is! List) return null;
    for (final item in list) {
      if (item is! Map) continue;
      for (final key in idKeys) {
        final id = item[key];
        // Ollama lists a model requested as plain `llama3` as `llama3:latest`.
        if (id == model || id == '$model:latest') return item;
      }
    }
    return null;
  }

  static int? _positive(Object? value) {
    final n = switch (value) {
      num v => v.toInt(),
      String v => int.tryParse(v.trim()),
      _ => null,
    };
    return n != null && n > 0 ? n : null;
  }
}
