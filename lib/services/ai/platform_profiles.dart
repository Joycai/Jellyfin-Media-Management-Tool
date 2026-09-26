/// Platform profiles: what a vendor, relay or local server offers, as data.
///
/// A channel is one credential on one host; a route is one protocol that
/// credential can speak there. What differs between vendors — which
/// protocols a host offers and at which path, how it switches reasoning,
/// which private fields exist — enters the app only through this table, never
/// as a vendor branch in an adapter. Every row's [RouteSpec.source] says where
/// the fact came from, so a reviewer can tell a measured fact from a
/// documented one.
///
/// A host that matches no profile is [PlatformProfiles.custom]: protocol
/// standard fields only, and the local-server ladders for everything else —
/// which is exactly how every endpoint behaved before profiles existed.
library;

import 'ai_provider.dart';
import 'learned_behaviour.dart';
import 'thinking_dialect.dart';

/// Where a platform runs.
enum PlatformKind { vendor, relay, local, custom }

/// How a route switches reasoning now, after what it has refused — what the
/// adapters send, read by the settings screens so that none of them works it
/// out on its own ([PlatformProfiles.reasoningRouteFor]).
enum ReasoningRoute {
  /// A platform's field, sent both ways: a Chat Completions dialect, or a
  /// Messages route declared as a switch.
  platformField,

  /// The protocol's own field: Messages' `thinking`, sent only for on, and
  /// Responses' `reasoning.effort`.
  protocolField,

  /// On was refused and is no longer sent, but off still is (a Messages
  /// switch route that refused `adaptive` still says `disabled`): the toggle
  /// can still turn reasoning off, and on leaves the model at its default.
  onRefused,

  /// Off was refused, so off sends nothing and the model runs at its own
  /// default — which reasons. On is still sent, unless the field was later
  /// refused by name too; the model reasons either way.
  offRefused,

  /// Sent neither way: the field refused by name, or on a Messages route
  /// every form of thinking — where off is the protocol's default anyway.
  refused,

  /// No switch at all: the local-server ladder, judged by the reply.
  ladder;

  /// Whether the settings toggle changes what this route sends.
  bool get switchable =>
      this == platformField || this == protocolField || this == onRefused;

  /// What a toggle for a model no preset knows is drawn as, whatever was
  /// saved; null where it shows the saved choice.
  bool? get drawnAs => switch (this) {
    offRefused => true,
    refused => false,
    platformField || protocolField || onRefused || ladder => null,
  };
}

/// One protocol on one platform.
class RouteSpec {
  /// Appended to the channel's host when the route has no endpoint of its
  /// own. Empty means the host itself: the adapter adds its own version
  /// segment to a bare origin.
  final String defaultPath;

  /// How the platform switches reasoning on this route, or null for no
  /// documented switch (the local-server ladder then applies).
  final ThinkingDialect? thinkingDialect;

  /// A Messages route whose platform takes thinking as a switch: on is
  /// `{type: "adaptive"}` with no `display`, off is `{type: "disabled"}`
  /// (KB 03 §3, the `switch` dialect). Declared for a platform that thinks
  /// unless told not to, or that accepts only those two types; anywhere
  /// else off sends nothing and on takes the model's own form.
  ///
  /// A bool rather than a [ThinkingDialect]: those produce Chat Completions'
  /// field shapes (`thinkingType` sends `enabled` with no budget), which
  /// would be the wrong bytes on Messages.
  final bool messagesThinkingSwitch;

  /// The platform's own documentation, or a measurement, behind this row.
  final String source;

  const RouteSpec({
    this.defaultPath = '',
    this.thinkingDialect,
    this.messagesThinkingSwitch = false,
    required this.source,
  });
}

class PlatformProfile {
  final String id;

  /// A product name, shown as is. Generic kinds (relay, custom, local) are
  /// named by the UI from its own strings.
  final String name;
  final PlatformKind kind;

  /// Hosts this platform is recognised by. A subdomain matches too.
  final List<String> hosts;

  /// Where a new channel on this platform points by default.
  final String defaultBaseUrl;

  /// The protocols the platform offers, primary first.
  final Map<AiProviderType, RouteSpec> routes;

  /// Whether a key is required. Local servers run without one.
  final bool needsKey;

  const PlatformProfile({
    required this.id,
    required this.name,
    required this.kind,
    this.hosts = const [],
    this.defaultBaseUrl = '',
    required this.routes,
    this.needsKey = true,
  });

  AiProviderType get primaryProtocol => routes.keys.first;

  bool matchesHost(String host) =>
      hosts.any((h) => host == h || host.endsWith('.$h'));
}

abstract final class PlatformProfiles {
  static const _vendorDocs = '【文档 2026-08】vendor API reference';

  static const openAi = PlatformProfile(
    id: 'openai',
    name: 'OpenAI',
    kind: PlatformKind.vendor,
    hosts: ['api.openai.com'],
    defaultBaseUrl: 'https://api.openai.com',
    routes: {
      AiProviderType.openAi: RouteSpec(defaultPath: '/v1', source: _vendorDocs),
      AiProviderType.openAiResponses: RouteSpec(
        defaultPath: '/v1',
        source: '【文档 2026-08】platform.openai.com/docs/api-reference/responses',
      ),
    },
  );

  static const anthropic = PlatformProfile(
    id: 'anthropic',
    name: 'Anthropic',
    kind: PlatformKind.vendor,
    hosts: ['api.anthropic.com'],
    defaultBaseUrl: 'https://api.anthropic.com',
    routes: {
      AiProviderType.anthropic: RouteSpec(
        source: '【文档 2026-08】docs.anthropic.com/en/api/messages',
      ),
    },
  );

  static const google = PlatformProfile(
    id: 'google',
    name: 'Google Gemini',
    kind: PlatformKind.vendor,
    hosts: ['generativelanguage.googleapis.com'],
    defaultBaseUrl: 'https://generativelanguage.googleapis.com',
    routes: {
      AiProviderType.googleGenAi: RouteSpec(
        source: '【文档 2026-08】ai.google.dev/api/generate-content',
      ),
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/v1beta/openai',
        source: '【文档 2026-08】ai.google.dev/gemini-api/docs/openai',
      ),
    },
  );

  static const deepSeek = PlatformProfile(
    id: 'deepseek',
    name: 'DeepSeek',
    kind: PlatformKind.vendor,
    hosts: ['api.deepseek.com'],
    defaultBaseUrl: 'https://api.deepseek.com',
    routes: {
      AiProviderType.openAi: RouteSpec(
        thinkingDialect: ThinkingDialect.thinkingType,
        source: '【文档 2026-08】api-docs.deepseek.com · thinking.type',
      ),
      AiProviderType.anthropic: RouteSpec(
        defaultPath: '/anthropic',
        source: '【文档 2026-08】api-docs.deepseek.com/guides/anthropic_api',
      ),
    },
  );

  static const dashScope = PlatformProfile(
    id: 'dashscope',
    name: '阿里云百炼',
    kind: PlatformKind.vendor,
    // One host per region (dashscope-intl, dashscope-us, …); see [forHost].
    hosts: ['dashscope.aliyuncs.com'],
    defaultBaseUrl: 'https://dashscope.aliyuncs.com',
    routes: {
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/compatible-mode/v1',
        thinkingDialect: ThinkingDialect.enableThinking,
        source: '【文档 2026-08】help.aliyun.com/model-studio · enable_thinking',
      ),
      AiProviderType.anthropic: RouteSpec(
        defaultPath: '/apps/anthropic',
        source: '【文档 2026-08】help.aliyun.com/model-studio · Anthropic API',
      ),
    },
  );

  static const zhipu = PlatformProfile(
    id: 'zhipu',
    name: '智谱 BigModel',
    kind: PlatformKind.vendor,
    hosts: ['bigmodel.cn', 'api.z.ai'],
    defaultBaseUrl: 'https://open.bigmodel.cn',
    routes: {
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/api/paas/v4',
        thinkingDialect: ThinkingDialect.thinkingType,
        source: '【实测 2026-09-19】glm-4.6 · thinking.type',
      ),
      AiProviderType.anthropic: RouteSpec(
        defaultPath: '/api/anthropic',
        source: '【文档 2026-08】docs.bigmodel.cn · Anthropic API',
      ),
    },
  );

  static const volcengine = PlatformProfile(
    id: 'volcengine',
    name: '火山方舟',
    kind: PlatformKind.vendor,
    hosts: ['volces.com'],
    defaultBaseUrl: 'https://ark.cn-beijing.volces.com',
    routes: {
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/api/v3',
        thinkingDialect: ThinkingDialect.thinkingType,
        source:
            '【文档 2026-08】volcengine.com/docs/82379 · thinking.type '
            '(实测 2026-09-18: reasoning_effort "none" also took)',
      ),
    },
  );

  static const xai = PlatformProfile(
    id: 'xai',
    name: 'xAI',
    kind: PlatformKind.vendor,
    hosts: ['api.x.ai'],
    defaultBaseUrl: 'https://api.x.ai',
    routes: {
      AiProviderType.openAiResponses: RouteSpec(
        defaultPath: '/v1',
        source: '【文档 2026-08】docs.x.ai · Responses is the recommended API',
      ),
      AiProviderType.openAi: RouteSpec(defaultPath: '/v1', source: _vendorDocs),
    },
  );

  static const miniMax = PlatformProfile(
    id: 'minimax',
    name: 'MiniMax',
    kind: PlatformKind.vendor,
    hosts: ['minimaxi.com', 'minimax.io'],
    defaultBaseUrl: 'https://api.minimaxi.com',
    routes: {
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/v1',
        source: '【文档 2026-08】platform.minimaxi.com · base_resp',
      ),
      AiProviderType.anthropic: RouteSpec(
        defaultPath: '/anthropic',
        // Sent `enabled` + budget, a 400 would once have switched thinking
        // off for the route; only these two types are taken.
        messagesThinkingSwitch: true,
        source:
            '【文档 2026-08】platform.minimaxi.com · Anthropic API; '
            '【KB 03 §3】MiniMax-M3 /anthropic: adaptive | disabled',
      ),
    },
  );

  static const openRouter = PlatformProfile(
    id: 'openrouter',
    name: 'OpenRouter',
    kind: PlatformKind.relay,
    hosts: ['openrouter.ai'],
    defaultBaseUrl: 'https://openrouter.ai',
    routes: {
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/api/v1',
        thinkingDialect: ThinkingDialect.reasoningObject,
        source: '【文档 2026-08】openrouter.ai/docs · reasoning.enabled',
      ),
    },
  );

  /// A New API / One API style relay: one key, every protocol it mirrors.
  static const relay = PlatformProfile(
    id: 'relay',
    name: 'relay',
    kind: PlatformKind.relay,
    routes: {
      AiProviderType.openAi: RouteSpec(
        defaultPath: '/v1',
        source: '【中继源码】New API relay routes',
      ),
      AiProviderType.openAiResponses: RouteSpec(
        defaultPath: '/v1',
        source: '【中继源码】New API relay routes',
      ),
      AiProviderType.anthropic: RouteSpec(source: '【中继源码】New API relay routes'),
      AiProviderType.googleGenAi: RouteSpec(
        source: '【中继源码】New API relay routes',
      ),
    },
  );

  static const lmStudio = PlatformProfile(
    id: 'lmstudio',
    name: 'LM Studio',
    kind: PlatformKind.local,
    defaultBaseUrl: 'http://localhost:1234',
    needsKey: false,
    routes: {AiProviderType.openAi: RouteSpec(source: '【实现】lmstudio.ai/docs')},
  );

  static const ollama = PlatformProfile(
    id: 'ollama',
    name: 'Ollama',
    kind: PlatformKind.local,
    defaultBaseUrl: 'http://localhost:11434',
    needsKey: false,
    routes: {
      AiProviderType.openAi: RouteSpec(source: '【实现】ollama.com/blog/openai'),
    },
  );

  static const llamaCpp = PlatformProfile(
    id: 'llamacpp',
    name: 'llama.cpp / vLLM',
    kind: PlatformKind.local,
    defaultBaseUrl: 'http://localhost:8080',
    needsKey: false,
    routes: {
      AiProviderType.openAi: RouteSpec(
        source: '【实现】llama.cpp server · vLLM OpenAI server',
      ),
    },
  );

  /// Protocol standard fields only — today's behaviour for any endpoint.
  static const custom = PlatformProfile(
    id: 'custom',
    name: 'custom',
    kind: PlatformKind.custom,
    needsKey: false,
    routes: {
      AiProviderType.openAi: RouteSpec(source: 'protocol standard'),
      AiProviderType.googleGenAi: RouteSpec(source: 'protocol standard'),
      AiProviderType.anthropic: RouteSpec(source: 'protocol standard'),
      AiProviderType.openAiResponses: RouteSpec(source: 'protocol standard'),
    },
  );

  /// Every profile, in the order the add-channel picker lists them.
  static const all = [
    openAi,
    anthropic,
    google,
    deepSeek,
    dashScope,
    zhipu,
    volcengine,
    xai,
    miniMax,
    openRouter,
    relay,
    lmStudio,
    ollama,
    llamaCpp,
    custom,
  ];

  static PlatformProfile byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => custom);

  /// The platform an endpoint's host belongs to, or null when no profile
  /// claims it. Local servers and relays have no fixed host, so only a
  /// channel created from their profile is one.
  static PlatformProfile? forHost(String endpoint) {
    final host = Uri.tryParse(endpoint.trim())?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    for (final profile in all) {
      if (profile.matchesHost(host)) return profile;
    }
    // DashScope names each region's host `dashscope-<region>.aliyuncs.com`,
    // and a subdomain of the plain host is a region too.
    final labels = host.split('.');
    if (host.endsWith('.aliyuncs.com') &&
        labels.length >= 3 &&
        labels[labels.length - 3].startsWith('dashscope')) {
      return dashScope;
    }
    return null;
  }

  /// The platform [config] runs on: its channel's, else what its host
  /// implies, else [custom].
  static PlatformProfile of(AiConfig config) => config.platform != null
      ? byId(config.platform)
      : (forHost(config.endpoint) ?? custom);

  /// How [config]'s route switches reasoning, or null for the ladder.
  static ThinkingDialect? dialectFor(AiConfig config) =>
      of(config).routes[config.provider]?.thinkingDialect;

  /// Whether [config]'s route is a Messages route that takes thinking as a
  /// switch — see [RouteSpec.messagesThinkingSwitch].
  static bool messagesSwitchFor(AiConfig config) =>
      config.provider == AiProviderType.anthropic &&
      (of(config).routes[config.provider]?.messagesThinkingSwitch ?? false);

  /// How [config]'s route switches reasoning after what it [learned], and
  /// the field it does it with. Mirrors each adapter's own reading of the
  /// same memory; `platform_profiles_test` holds the two side by side.
  ///
  /// A refused off is checked before a field refused by name, on every
  /// protocol: it says the model reasons, where the name alone says only
  /// that nothing is sent, and either way nothing goes out for off.
  static ({ReasoningRoute route, String? field}) reasoningRouteFor(
    AiConfig config,
    LearnedBehaviour learned,
  ) {
    final tried = learned.thinkingOffTried;
    final refused = learned.rejectedFields;
    switch (config.provider) {
      case AiProviderType.openAi:
        final field = dialectFor(config)?.field(thinking: false).key;
        if (field == null) return (route: ReasoningRoute.ladder, field: null);
        if (tried.contains(LearnedBehaviour.dialectOff)) {
          return (route: ReasoningRoute.offRefused, field: field);
        }
        if (refused.contains(field)) {
          return (route: ReasoningRoute.refused, field: field);
        }
        return (route: ReasoningRoute.platformField, field: field);
      case AiProviderType.googleGenAi:
        return (route: ReasoningRoute.ladder, field: null);
      case AiProviderType.anthropic:
        // A switch route asks adaptive only, and says off as `disabled`.
        if (messagesSwitchFor(config)) {
          if (tried.contains(LearnedBehaviour.dialectOff)) {
            return (route: ReasoningRoute.offRefused, field: 'thinking');
          }
          final forms = MessagesThinking.refusedIn(
            refused,
            first: MessagesThinking.adaptive,
          );
          return forms.contains(MessagesThinking.adaptive)
              ? (route: ReasoningRoute.onRefused, field: 'thinking')
              : (route: ReasoningRoute.platformField, field: 'thinking');
        }
        // Elsewhere off is the protocol's default: nothing to refuse.
        final forms = MessagesThinking.refusedIn(
          refused,
          first: MessagesThinking.forModel(config.model),
        );
        return forms.length < MessagesThinking.values.length
            ? (route: ReasoningRoute.protocolField, field: 'thinking')
            : (route: ReasoningRoute.refused, field: 'thinking');
      case AiProviderType.openAiResponses:
        if (tried.contains(LearnedBehaviour.effortNone)) {
          return (route: ReasoningRoute.offRefused, field: 'reasoning.effort');
        }
        if (refused.contains('reasoning')) {
          return (route: ReasoningRoute.refused, field: 'reasoning.effort');
        }
        return (route: ReasoningRoute.protocolField, field: 'reasoning.effort');
    }
  }
}
