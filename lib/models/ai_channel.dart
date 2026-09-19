/// Channel × route × model: how the app stores its AI endpoints.
///
/// - A **channel** is one credential on one host (a vendor account, a relay,
///   a local server). The key is stored once, on the channel.
/// - A **route** is one protocol that credential can speak on that host —
///   Chat Completions, Responses, Gemini, Anthropic. At most one per protocol.
/// - A **model** hangs off the channel and picks one of its routes. Its
///   parameters are kept per route ([RouteParams]): switching a model to
///   another route parks the old route's values and never copies them over,
///   because a value tuned for one protocol can mean something else, or be
///   refused, on another.
///
/// Every consumer below this layer still receives one flat [AiConfig] — see
/// [AiChannel.configFor] — so the providers, the agent loop and the tasks do
/// not know channels exist.
library;

import '../services/ai/ai_provider.dart';
import '../services/ai/platform_profiles.dart';
import '../utils/ids.dart';

/// Parameters that belong to a model *on one route*: they change meaning, or
/// stop existing, when the protocol changes.
class RouteParams {
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? minP;
  final double? presencePenalty;
  final double? repeatPenalty;
  final bool thinkingEnabled;
  final int? maxOutputTokens;
  final ToolSupport? toolSupport;

  const RouteParams({
    this.temperature,
    this.topP,
    this.topK,
    this.minP,
    this.presencePenalty,
    this.repeatPenalty,
    this.thinkingEnabled = false,
    this.maxOutputTokens,
    this.toolSupport,
  });

  static const empty = RouteParams();

  factory RouteParams.fromConfig(AiConfig config) => RouteParams(
    temperature: config.temperature,
    topP: config.topP,
    topK: config.topK,
    minP: config.minP,
    presencePenalty: config.presencePenalty,
    repeatPenalty: config.repeatPenalty,
    thinkingEnabled: config.thinkingEnabled,
    maxOutputTokens: config.maxOutputTokens,
    toolSupport: config.toolSupport,
  );

  /// The same JSON keys [AiConfig] uses, so a value means one thing wherever
  /// it is stored.
  Map<String, Object?> toJson() => {
    'temperature_override': temperature,
    'top_p': topP,
    'top_k': topK,
    'min_p': minP,
    'presence_penalty': presencePenalty,
    'repeat_penalty': repeatPenalty,
    'thinking_enabled': thinkingEnabled,
    'max_output_tokens': maxOutputTokens,
    'tool_support': toolSupport?.toJson(),
  };

  factory RouteParams.fromJson(Map<String, dynamic> json) => RouteParams(
    temperature: AiConfig.decimal(json['temperature_override']),
    topP: AiConfig.decimal(json['top_p']),
    topK: AiConfig.tokenCount(json['top_k']),
    minP: AiConfig.decimal(json['min_p']),
    presencePenalty: AiConfig.decimal(json['presence_penalty']),
    repeatPenalty: AiConfig.decimal(json['repeat_penalty']),
    thinkingEnabled: json['thinking_enabled'] == true,
    maxOutputTokens: AiConfig.tokenCount(json['max_output_tokens']),
    toolSupport: ToolSupport.fromJson(json['tool_support']),
  );
}

/// One protocol on a channel.
class AiRoute {
  final AiProviderType protocol;

  /// Where this route talks to, when it is not the channel's host plus the
  /// platform's default path: a path starting with `/`, added to the host,
  /// or a full URL, which replaces the host too. A migrated profile keeps its
  /// URL here byte for byte, so the requests it sends do not change.
  final String? endpoint;

  const AiRoute({required this.protocol, this.endpoint});

  AiRoute withEndpoint(String? value) {
    final trimmed = value?.trim();
    return AiRoute(
      protocol: protocol,
      endpoint: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': protocol.id,
    'endpoint': ?endpoint,
  };

  static AiRoute? fromJson(Object? json) {
    if (json is! Map) return null;
    final protocol = AiProviderTypeX.tryFromId(json['protocol'] as String?);
    if (protocol == null) return null;
    final endpoint = json['endpoint'];
    return AiRoute(
      protocol: protocol,
      endpoint: endpoint is String && endpoint.trim().isNotEmpty
          ? endpoint
          : null,
    );
  }
}

/// A model on a channel.
class AiModelEntry {
  /// Stable id, which task assignments refer to. A migrated profile keeps its
  /// profile id here, so the old active profile becomes the organize model.
  final String id;

  /// The model name sent on the wire.
  final String upstream;

  /// See [AiConfig.contextWindow]. The model's, whatever route it takes.
  final int? contextWindow;

  /// The user allows images, and video frames, to be sent to this model. An
  /// authorization, not a capability: whether a route can carry them is the
  /// route's business.
  final bool imageInput;
  final bool videoInput;

  /// The route this model uses now.
  final AiProviderType route;

  /// Parameters per route. Only [route]'s are sent; the rest are parked.
  final Map<AiProviderType, RouteParams> params;

  const AiModelEntry({
    required this.id,
    required this.upstream,
    required this.route,
    this.contextWindow,
    this.imageInput = false,
    this.videoInput = false,
    this.params = const {},
  });

  factory AiModelEntry.create({
    required String upstream,
    required AiProviderType route,
  }) => AiModelEntry(id: newId(), upstream: upstream.trim(), route: route);

  RouteParams get current => params[route] ?? RouteParams.empty;

  /// Whether [protocol] has parameters of its own for this model.
  bool hasParamsFor(AiProviderType protocol) => params.containsKey(protocol);

  AiModelEntry copyWith({
    String? upstream,
    int? Function()? contextWindow,
    bool? imageInput,
    bool? videoInput,
    AiProviderType? route,
    Map<AiProviderType, RouteParams>? params,
  }) => AiModelEntry(
    id: id,
    upstream: upstream ?? this.upstream,
    contextWindow: contextWindow != null ? contextWindow() : this.contextWindow,
    imageInput: imageInput ?? this.imageInput,
    videoInput: videoInput ?? this.videoInput,
    route: route ?? this.route,
    params: params ?? this.params,
  );

  /// [params] with [route]'s replaced.
  AiModelEntry withCurrentParams(RouteParams value) =>
      copyWith(params: {...params, route: value});

  /// Moves this model to [protocol]. The current route's parameters stay
  /// parked under it; the new route starts from what it had before, or from
  /// nothing — never from a copy.
  AiModelEntry switchedTo(AiProviderType protocol) =>
      protocol == route ? this : copyWith(route: protocol);

  Map<String, Object?> toJson() => {
    'id': id,
    'upstream': upstream,
    'route': route.id,
    'context_window': contextWindow,
    if (imageInput) 'image_input': true,
    if (videoInput) 'video_input': true,
    'params': {
      for (final entry in params.entries) entry.key.id: entry.value.toJson(),
    },
  };

  static AiModelEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final upstream = json['upstream'];
    final route = AiProviderTypeX.tryFromId(json['route'] as String?);
    if (id is! String || upstream is! String || route == null) return null;
    final rawParams = json['params'];
    return AiModelEntry(
      id: id,
      upstream: upstream,
      route: route,
      contextWindow: AiConfig.tokenCount(json['context_window']),
      imageInput: json['image_input'] == true,
      videoInput: json['video_input'] == true,
      params: {
        if (rawParams is Map)
          for (final entry in rawParams.entries)
            if (AiProviderTypeX.tryFromId('${entry.key}')
                case final AiProviderType protocol)
              if (entry.value case final Map<String, dynamic> value)
                protocol: RouteParams.fromJson(value),
      },
    );
  }
}

/// One credential on one host.
class AiChannel {
  final String id;
  final String name;

  /// The platform profile, when it is not the one the host implies — a relay
  /// or a local server has no host of its own. Null infers it from [baseUrl].
  final String? platformId;

  /// The host, with any prefix shared by every route.
  final String baseUrl;
  final String apiKey;

  /// The enabled routes, primary first.
  final List<AiRoute> routes;
  final List<AiModelEntry> models;

  const AiChannel({
    required this.id,
    required this.name,
    this.platformId,
    required this.baseUrl,
    required this.apiKey,
    required this.routes,
    this.models = const [],
  });

  PlatformProfile get platform => platformId != null
      ? PlatformProfiles.byId(platformId)
      : (PlatformProfiles.forHost(baseUrl) ?? PlatformProfiles.custom);

  AiProviderType? get primaryProtocol => routes.firstOrNull?.protocol;

  AiRoute? routeFor(AiProviderType protocol) {
    for (final route in routes) {
      if (route.protocol == protocol) return route;
    }
    return null;
  }

  /// The URL [protocol] talks to: the route's own endpoint, else the host
  /// plus the platform's default path. Joined as strings, never through
  /// [Uri], which would lower-case the host and add slashes the user did not
  /// type.
  String endpointFor(AiProviderType protocol) {
    final own = routeFor(protocol)?.endpoint;
    if (own != null && !own.startsWith('/')) return own;
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (own != null) return '$base$own';
    final path = platform.routes[protocol]?.defaultPath ?? '';
    // A host pasted the way vendor docs print it already ends in the path
    // (`https://api.openai.com/v1`); adding it again would 404.
    return base.endsWith(path) ? base : '$base$path';
  }

  /// Whether the endpoint for [protocol] replaces the host rather than
  /// extending it — the route table shows "own host".
  bool hasOwnHost(AiProviderType protocol) {
    final own = routeFor(protocol)?.endpoint;
    if (own == null || own.startsWith('/')) return false;
    final mine = Uri.tryParse(own);
    final host = Uri.tryParse(baseUrl.trim());
    if (mine == null || host == null) return false;
    return mine.scheme != host.scheme ||
        mine.host != host.host ||
        mine.port != host.port;
  }

  /// The flat view the rest of the app runs on: [model] on its current
  /// route. A model whose route this channel no longer has falls back to the
  /// primary route.
  AiConfig configFor(AiModelEntry model) {
    final protocol = routeFor(model.route) != null
        ? model.route
        : (primaryProtocol ?? model.route);
    final params = model.params[protocol] ?? RouteParams.empty;
    return AiConfig(
      provider: protocol,
      endpoint: endpointFor(protocol),
      apiKey: apiKey,
      model: model.upstream,
      // A route on a host of its own belongs to that host's platform.
      platform: hasOwnHost(protocol)
          ? PlatformProfiles.forHost(endpointFor(protocol))?.id ?? platformId
          : platformId ?? PlatformProfiles.forHost(endpointFor(protocol))?.id,
      temperature: params.temperature,
      topP: params.topP,
      topK: params.topK,
      minP: params.minP,
      presencePenalty: params.presencePenalty,
      repeatPenalty: params.repeatPenalty,
      thinkingEnabled: params.thinkingEnabled,
      contextWindow: model.contextWindow,
      maxOutputTokens: params.maxOutputTokens,
      toolSupport: params.toolSupport,
      imageInput: model.imageInput,
      videoInput: model.videoInput,
    );
  }

  AiModelEntry? model(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  AiChannel copyWith({
    String? name,
    String? Function()? platformId,
    String? baseUrl,
    String? apiKey,
    List<AiRoute>? routes,
    List<AiModelEntry>? models,
  }) => AiChannel(
    id: id,
    name: name ?? this.name,
    platformId: platformId != null ? platformId() : this.platformId,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    routes: routes ?? this.routes,
    models: models ?? this.models,
  );

  /// This channel on another host. A route whose own endpoint was built on
  /// the old host — every migrated profile's is — moves with it; one on a
  /// host of its own stays where it is.
  AiChannel withBaseUrl(String value) {
    String bare(String url) {
      var s = url.trim();
      while (s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
      return s;
    }

    final old = bare(baseUrl);
    // Only a real host can be moved from: a half-typed `https:` would match
    // every route on every host.
    final movable = Uri.tryParse(old)?.host.isNotEmpty ?? false;
    return copyWith(
      baseUrl: value,
      routes: [
        for (final route in routes)
          if (route.endpoint case final own?
              when movable &&
                  !own.startsWith('/') &&
                  (bare(own) == old || own.startsWith('$old/')))
            route.withEndpoint('${bare(value)}${own.substring(old.length)}')
          else
            route,
      ],
    );
  }

  AiChannel withModel(AiModelEntry model) => copyWith(
    models: [
      for (final m in models)
        if (m.id == model.id) model else m,
      if (models.every((m) => m.id != model.id)) model,
    ],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': ?platformId,
    'base_url': baseUrl,
    'api_key': apiKey,
    'routes': [for (final route in routes) route.toJson()],
    'models': [for (final model in models) model.toJson()],
  };

  static AiChannel? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    final routes = [
      if (json['routes'] case final List<dynamic> list)
        for (final raw in list)
          if (AiRoute.fromJson(raw) case final AiRoute route) route,
    ];
    return AiChannel(
      id: id,
      name: json['name'] is String ? json['name'] as String : '',
      platformId: json['platform'] is String
          ? json['platform'] as String
          : null,
      baseUrl: json['base_url'] is String ? json['base_url'] as String : '',
      apiKey: json['api_key'] is String ? json['api_key'] as String : '',
      routes: routes,
      models: [
        if (json['models'] case final List<dynamic> list)
          for (final raw in list)
            if (AiModelEntry.fromJson(raw) case final AiModelEntry model) model,
      ],
    );
  }

  /// A one-route, one-model channel reproducing a pre-channel profile
  /// exactly: the route keeps the profile's URL verbatim and the model keeps
  /// the profile's id, so tool-support results, learned behaviour and the
  /// requests themselves are unchanged.
  factory AiChannel.fromLegacyProfile({
    required String id,
    required String name,
    required AiConfig config,
  }) => AiChannel(
    id: id,
    name: name,
    baseUrl: originOf(config.endpoint),
    apiKey: config.apiKey,
    routes: [AiRoute(protocol: config.provider, endpoint: config.endpoint)],
    models: [
      AiModelEntry(
        id: id,
        upstream: config.model,
        route: config.provider,
        contextWindow: config.contextWindow,
        params: {config.provider: RouteParams.fromConfig(config)},
      ),
    ],
  );

  /// `scheme://host:port` of [url], cut from the string as typed — never
  /// through [Uri], which would lower-case it.
  static String originOf(String url) {
    final trimmed = url.trim();
    final scheme = trimmed.indexOf('://');
    if (scheme < 0) return trimmed;
    final path = trimmed.indexOf('/', scheme + 3);
    return path < 0 ? trimmed : trimmed.substring(0, path);
  }

  /// A new, empty channel on [platform].
  factory AiChannel.create({
    required PlatformProfile platform,
    required String name,
    String? baseUrl,
    String apiKey = '',
  }) => AiChannel(
    id: newId(),
    name: name,
    platformId: platform.id,
    baseUrl: baseUrl ?? platform.defaultBaseUrl,
    apiKey: apiKey,
    routes: [AiRoute(protocol: platform.primaryProtocol)],
  );
}

/// The tasks a model can be assigned to.
enum AiTask {
  /// Organize a folder: a tool loop.
  organize,

  /// Scrape: have the model write a recipe for a site.
  scrapeLearn,

  /// Scrape: have the model read the page itself.
  scrapeDirect,

  /// Look at frames and posters. Needs image input.
  vision;

  String get id => name;

  /// Whether the task runs as a tool loop, so only a model known to call
  /// tools qualifies.
  bool get needsTools => this != vision;

  static AiTask? fromId(String? id) {
    for (final task in values) {
      if (task.id == id) return task;
    }
    return null;
  }
}
