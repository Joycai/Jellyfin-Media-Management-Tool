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

import 'dart:io';

import 'ai_provider.dart';
import 'learned_behaviour.dart';
import 'thinking_dialect.dart';

/// Where a platform runs.
enum PlatformKind { vendor, relay, local, custom }

/// Whose server a route talks to, for advice about its settings
/// ([PlatformProfiles.serverOwner]).
enum ServerOwner {
  /// The user's: an address on this computer or a private network, on a
  /// channel not declared a vendor's or a relay's. Its model settings are
  /// theirs to change.
  own,

  /// Someone else's: a vendor's platform, or a relay's, on a public name.
  other,

  /// Not known: a public name on a channel that is not a vendor's or a
  /// relay's (a VPS of their own, a cloud with no profile, a relay typed in
  /// without its profile, a local platform's profile pointed at a hosted
  /// service), or a private address on one that is (a proxy on their
  /// network in front of a cloud, or their own server under a vendor's
  /// profile). The address does not say, or says otherwise than the
  /// declaration, and nothing is asked to guess.
  unknown,
}

/// How a Messages switch route says off, in the order tried: each once per
/// model, the next once the one before was refused, and nothing once both
/// were ([PlatformProfiles.messagesOffFor]). What was refused is kept in
/// `LearnedBehaviour.thinkingOffTried`, under the rung's [triedMarker].
enum MessagesOff {
  /// `thinking: {type: "disabled"}`, the platform's switch.
  disabled(LearnedBehaviour.dialectOff),

  /// `output_config: {effort: "low"}`, the least reasoning, for a model that
  /// said it cannot stop. Not the same as off: 【实测 2026-09-28】with tools,
  /// Zhipu's glm-5.3 then returns no thinking block (64 output tokens, 1449
  /// without it), glm-5.3-flash and MiniMax-M2.5 through DashScope still
  /// think a little. `low` is the least value both platforms take — Zhipu's
  /// 5.3 refuses `medium`, `minimal` and `none` with the same "始终思考" — and
  /// it cannot go beside `disabled` (the pair draws that refusal too).
  leastEffort(LearnedBehaviour.leastEffortOff);

  /// What `thinkingOffTried` records once this rung was refused.
  final String triedMarker;

  const MessagesOff(this.triedMarker);

  /// The field this rung says off with, as the settings screens name it.
  String get field => switch (this) {
    disabled => 'thinking',
    leastEffort => 'output_config.effort',
  };

  /// The fields this rung adds to the request body.
  Map<String, Object> get body => switch (this) {
    disabled => const {
      'thinking': {'type': 'disabled'},
    },
    leastEffort => const {
      'output_config': {'effort': 'low'},
    },
  };

  /// The rung [payload] said off with, if it did.
  static MessagesOff? sentIn(Map<String, Object?> payload) =>
      switch ((payload['thinking'], payload['output_config'])) {
        ({'type': 'disabled'}, _) => disabled,
        (null, {'effort': 'low'}) => leastEffort,
        _ => null,
      };
}

/// One way a Chat Completions route says off: the field it adds to the
/// request, and the name `LearnedBehaviour.thinkingOffTried` keeps it under
/// once refused. A route's ways, in the order tried, are
/// [PlatformProfiles.chatOffRungsFor]; the next one is
/// [PlatformProfiles.chatOffFor].
typedef ChatOff = ({String marker, MapEntry<String, Object> field});

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

  /// The model said it cannot stop reasoning (on Chat Completions, or a
  /// Messages switch route, once the least was refused too where the route
  /// asks it), so off sends nothing and the model reasons at its
  /// default. On is still sent, unless on was later refused too (the field
  /// by name, or `adaptive` on a switch route); the model reasons either way.
  offRefused,

  /// The model said it cannot stop reasoning (it refused the switch set to
  /// off), so off asks for the least of it — which may stop it or only lower
  /// it: on a Messages switch route `output_config.effort: low`
  /// ([MessagesOff.leastEffort]), on a Chat Completions route that declares
  /// it `reasoning_effort: low` ([PlatformProfiles.chatLeast]). On is still
  /// sent unless it was refused too (`adaptive`, or the field by name); off
  /// differs either way, so the toggle stays live, and this outranks a
  /// refused on.
  offLeast,

  /// Off was refused without saying why, so off sends nothing and the
  /// model runs at its default — which may or may not reason: Responses
  /// refuses `effort: none` alike from a model that always reasons (Grok,
  /// o3) and from one that cannot reason at all (GPT-4.1). On is still
  /// sent; only a test shows what off does.
  offToDefault,

  /// Sent neither way: the field refused by name, or on a Messages route
  /// every form of thinking — where off is the protocol's default anyway,
  /// except on a switch route, whose platform may think by default.
  refused,

  /// No switch at all: the local-server ladder, judged by the reply.
  ladder;

  /// Whether a model no preset knows gets a live toggle here: where turning
  /// it can change whether the model reasons. Not where the model said it
  /// cannot stop and off sends nothing (on may still be sent, but it
  /// reasons either way) — where off asks for the least instead, the two
  /// send different things — and not the ladder, which has nothing to send
  /// for on.
  bool get switchable =>
      this == platformField ||
      this == protocolField ||
      this == onRefused ||
      this == offLeast ||
      this == offToDefault;

  /// What a toggle for a model no preset knows is drawn as, whatever was
  /// saved; null where it shows the saved choice.
  bool? get drawnAs => switch (this) {
    offRefused => true,
    refused => false,
    platformField ||
    protocolField ||
    onRefused ||
    offLeast ||
    offToDefault ||
    ladder => null,
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

  /// A Chat Completions route whose model may say it cannot stop reasoning
  /// (refuse [thinkingDialect]'s switch set to off): off then asks for the
  /// least of it, `reasoning_effort: "low"` ([PlatformProfiles.chatLeast]),
  /// before it sends nothing. Declared where measured: the value means
  /// other things elsewhere (DeepSeek folds `low` into `high`).
  final bool chatLeastEffort;

  /// The platform's own documentation, or a measurement, behind this row.
  final String source;

  const RouteSpec({
    this.defaultPath = '',
    this.thinkingDialect,
    this.messagesThinkingSwitch = false,
    this.chatLeastEffort = false,
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
        // Thinks unless told not to: deepseek-v4-pro and deepseek-flash
        // answer a request with no `thinking` with a thinking block, take
        // `disabled` (no block) and `adaptive`; `budget_tokens` is ignored.
        messagesThinkingSwitch: true,
        source:
            '【文档 2026-08】api-docs.deepseek.com/guides/anthropic_api; '
            '【实测 2026-09-28】thinks by default, disabled | adaptive taken',
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
        // Qwen (3.8-flash, 3.7-flash, 3.5-plus) thinks unless told not to
        // and takes `disabled` and `adaptive`. The third-party models on
        // the same face are learned one by one: MiniMax-M2.5 and glm-5.3
        // refuse `disabled` in the face's own `enable_thinking`
        // ("restricted to True", `MessagesRefusal`), kimi-k2-thinking
        // takes it and thinks anyway (the connection test's judge).
        messagesThinkingSwitch: true,
        source:
            '【文档 2026-08】help.aliyun.com/model-studio · Anthropic API; '
            '【实测 2026-09-28】Qwen thinks by default, disabled | adaptive taken',
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
        // The 5.3 generation refuses `disabled` with code 1210 and takes
        // `reasoning_effort: low`: with tools, glm-5.3 then reasoned 0–131
        // tokens a request where it reasoned 232–1476 at its default, and
        // decided every group alike, though twice without the year the
        // default gave. It answers a value it will not take (`medium`,
        // `none`) in the same words (measured 2026-09-19).
        chatLeastEffort: true,
        source:
            '【实测 2026-09-19】glm-4.6 · thinking.type; '
            '【实测 2026-09-28】5.3 refuses disabled (1210), takes low',
      ),
      AiProviderType.anthropic: RouteSpec(
        defaultPath: '/api/anthropic',
        // Thinks unless told not to. glm-4.6 takes `disabled`; the 5.3
        // generation refuses it with code 1210 ("该模型始终思考，不支持关闭
        // 思考；请使用 low、high 或 max") and is remembered as the model
        // that cannot stop (`dialectOff`), one request once.
        messagesThinkingSwitch: true,
        source:
            '【文档 2026-08】docs.bigmodel.cn · Anthropic API; '
            '【实测 2026-09-28】thinks by default, disabled taken on 4.6, '
            '1210 on 5.3',
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

  /// Whose server [config] talks to — so that advice about its model
  /// settings is given where the user can act on it, and only there. Read
  /// by the model page where the last test showed reasoning that was asked
  /// off. Two things speak, and neither guesses: the address, which says
  /// "the user's own" when it is on this computer or a private network
  /// ([privateHost]) and nothing on a public name; and the declaration,
  /// which says "someone else's" for a vendor's platform or a relay's and
  /// nothing otherwise (a local platform's profile names software, not
  /// whose machine runs it). One voice decides; none, or two that disagree,
  /// is [ServerOwner.unknown].
  static ServerOwner serverOwner(AiConfig config) {
    final kind = of(config).kind;
    final hosted = kind == PlatformKind.vendor || kind == PlatformKind.relay;
    final private = privateHost(config.endpoint);
    if (private && !hosted) return ServerOwner.own;
    if (!private && hosted) return ServerOwner.other;
    return ServerOwner.unknown;
  }

  /// Whether [endpoint] names this computer or a private network, by the
  /// names and address blocks reserved for that: `localhost` and
  /// `.localhost` (RFC 6761), `.local` (RFC 6762), `.home.arpa` (RFC 8375),
  /// `.internal` (ICANN); the unspecified address a server was started on
  /// (`0.0.0.0`, `::`), loopback, link-local, private (RFC 1918), shared
  /// (RFC 6598, `100.64/10`) and unique-local (RFC 4193) addresses, an IPv4
  /// address carried in IPv6 read as that address. No other name is read
  /// — `.lan`, a tailnet's `.ts.net`, a public name — since none of them
  /// says whose the server is.
  static bool privateHost(String endpoint) {
    final host = Uri.tryParse(endpoint.trim())?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        _privateNames.any((suffix) => host.endsWith(suffix))) {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    var bytes = address.rawAddress;
    if (bytes.length == 16) {
      // An IPv4 address carried in IPv6 (`::ffff:a.b.c.d`) is that address.
      final mapped =
          bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (mapped) {
        bytes = bytes.sublist(12);
      } else {
        // Unspecified, loopback, link-local (fe80::/10) or fc00::/7.
        return bytes.every((b) => b == 0) ||
            address.isLoopback ||
            (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
            (bytes[0] & 0xfe) == 0xfc;
      }
    }
    return bytes.every((b) => b == 0) ||
        bytes[0] == 10 ||
        bytes[0] == 127 ||
        (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }

  static const _privateNames = [
    '.localhost',
    '.local',
    '.internal',
    '.home.arpa',
  ];

  /// How [config]'s route switches reasoning, or null for the ladder.
  static ThinkingDialect? dialectFor(AiConfig config) =>
      of(config).routes[config.provider]?.thinkingDialect;

  /// The least reasoning on Chat Completions: the last way of saying off on
  /// a route that declares [RouteSpec.chatLeastEffort].
  static const ChatOff chatLeast = (
    marker: LearnedBehaviour.leastEffortOff,
    field: MapEntry('reasoning_effort', 'low'),
  );

  /// The ways [config]'s Chat Completions route says off, in the order
  /// tried: the platform's switch set to off, then — where the route
  /// declares it — [chatLeast]. None without a platform switch (the
  /// local-server ladder applies there).
  static List<ChatOff> chatOffRungsFor(AiConfig config) {
    final route = of(config).routes[config.provider];
    final dialect = route?.thinkingDialect;
    if (route == null || dialect == null) return const [];
    return [
      (
        marker: LearnedBehaviour.dialectOff,
        field: dialect.field(thinking: false),
      ),
      if (route.chatLeastEffort) chatLeast,
    ];
  }

  /// How [config]'s Chat Completions route says off after what it
  /// [learned]: the first of [chatOffRungsFor] not yet refused, or null
  /// where off sends nothing — every way refused, or the next one's field
  /// refused by name (never sent again; the switch refused so, a server that
  /// does not know the field, has said nothing of a model that cannot stop).
  /// The adapter's body, its reading of a refusal, its preview and
  /// [reasoningRouteFor] all read it, so none of them can disagree.
  static ChatOff? chatOffFor(AiConfig config, LearnedBehaviour learned) {
    for (final rung in chatOffRungsFor(config)) {
      if (learned.thinkingOffTried.contains(rung.marker)) continue;
      return learned.rejectedFields.contains(rung.field.key) ? null : rung;
    }
    return null;
  }

  /// The field the least reasoning goes out in on [config]'s protocol, as
  /// the settings screens name it: `reasoning_effort` on Chat Completions
  /// ([chatLeast]), `output_config.effort` on Messages
  /// ([MessagesOff.leastEffort]).
  static String leastEffortFieldFor(AiConfig config) =>
      config.provider == AiProviderType.openAi
      ? chatLeast.field.key
      : MessagesOff.leastEffort.field;

  /// The field [config]'s route asks reasoning on in after what it
  /// [learned], where it is a platform's or Messages' `thinking`, or null
  /// where on sends nothing: the platform's switch unless refused by name on
  /// Chat Completions, `thinking` while a form is left on Messages. The
  /// route-switch dialog reads it where off asks for the least.
  static String? reasoningOnFieldFor(
    AiConfig config,
    LearnedBehaviour learned,
  ) => switch (config.provider) {
    AiProviderType.openAi => switch (dialectFor(
      config,
    )?.field(thinking: true).key) {
      final key? when !learned.rejectedFields.contains(key) => key,
      _ => null,
    },
    AiProviderType.anthropic =>
      messagesOnFormFor(config, learned) != null ? 'thinking' : null,
    AiProviderType.googleGenAi || AiProviderType.openAiResponses => null,
  };

  /// Whether [config]'s route is a Messages route that takes thinking as a
  /// switch — see [RouteSpec.messagesThinkingSwitch].
  static bool messagesSwitchFor(AiConfig config) =>
      config.provider == AiProviderType.anthropic &&
      (of(config).routes[config.provider]?.messagesThinkingSwitch ?? false);

  /// How [config]'s Messages route says off after what it [learned], or
  /// null where off sends nothing: not a switch route (off is the protocol's
  /// default there), the `thinking` field refused by name before off was (a
  /// server that does not know the field has said nothing of a model that
  /// cannot stop), or every rung refused. The adapter's body and
  /// [reasoningRouteFor] both read it, so the two cannot disagree.
  static MessagesOff? messagesOffFor(
    AiConfig config,
    LearnedBehaviour learned,
  ) {
    if (!messagesSwitchFor(config)) return null;
    final tried = learned.thinkingOffTried;
    final fieldRefused =
        MessagesThinking.refusedIn(
          learned.rejectedFields,
          first: messagesFirstFormFor(config),
        ).length ==
        MessagesThinking.values.length;
    if (fieldRefused && !tried.contains(LearnedBehaviour.dialectOff)) {
      return null;
    }
    return MessagesOff.values
        .where((rung) => !tried.contains(rung.triedMarker))
        .firstOrNull;
  }

  /// The form [config]'s Messages route asks thinking in with it on, after
  /// what it [learned]: the model's own first, the other once that was
  /// refused, null once both were — a switch route asks adaptive only, the
  /// one form it takes. The adapter's body and the route-switch dialog both
  /// read it.
  static MessagesThinking? messagesOnFormFor(
    AiConfig config,
    LearnedBehaviour learned,
  ) {
    final first = messagesFirstFormFor(config);
    final refused = MessagesThinking.refusedIn(
      learned.rejectedFields,
      first: first,
    );
    final forms = messagesSwitchFor(config) ? [first] : [first, first.other];
    return forms.where((form) => !refused.contains(form)).firstOrNull;
  }

  /// The form [config]'s Messages route asks thinking in before any
  /// refusal: adaptive on a switch route, the one form it takes, otherwise
  /// the model's own. The adapter (through [messagesOnFormFor]), the
  /// refusal reading and [reasoningRouteFor] all read it.
  static MessagesThinking messagesFirstFormFor(AiConfig config) =>
      messagesSwitchFor(config)
      ? MessagesThinking.adaptive
      : MessagesThinking.forModel(config.model);

  /// How [config]'s route switches reasoning after what it [learned], and
  /// the field it does it with. Mirrors each adapter's own reading of the
  /// same memory; `platform_profiles_test` holds the two side by side.
  /// Whether a request asks for reasoning at all is not read here: that is
  /// [ResolvedSampling.thinking], the one value every adapter sends.
  ///
  /// Where a refused off says the model reasons (Chat Completions, a
  /// Messages switch route) it is checked before a field refused by name,
  /// which alone says only that nothing is sent. On Responses it says
  /// nothing of the kind, and a field refused by name as well means
  /// nothing goes out either way.
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
        final off = chatOffFor(config, learned);
        if (off?.marker == LearnedBehaviour.leastEffortOff) {
          return (
            route: ReasoningRoute.offLeast,
            field: leastEffortFieldFor(config),
          );
        }
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
        final forms = MessagesThinking.refusedIn(
          refused,
          first: messagesFirstFormFor(config),
        );
        // A switch route asks adaptive only, and says off as `disabled`. A
        // server there that does not know the field records every form,
        // and nothing is sent either way; one that refused the form still
        // takes `disabled`. (A legacy bare record is a verdict on
        // `enabled` alone, which a switch route never sends.)
        if (messagesSwitchFor(config)) {
          if (messagesOffFor(config, learned) == MessagesOff.leastEffort) {
            return (
              route: ReasoningRoute.offLeast,
              field: leastEffortFieldFor(config),
            );
          }
          if (tried.contains(LearnedBehaviour.dialectOff)) {
            return (route: ReasoningRoute.offRefused, field: 'thinking');
          }
          if (forms.length == MessagesThinking.values.length) {
            return (route: ReasoningRoute.refused, field: 'thinking');
          }
          return forms.contains(MessagesThinking.adaptive)
              ? (route: ReasoningRoute.onRefused, field: 'thinking')
              : (route: ReasoningRoute.platformField, field: 'thinking');
        }
        // Elsewhere off is the protocol's default: nothing to refuse.
        return forms.length < MessagesThinking.values.length
            ? (route: ReasoningRoute.protocolField, field: 'thinking')
            : (route: ReasoningRoute.refused, field: 'thinking');
      case AiProviderType.openAiResponses:
        if (refused.contains('reasoning')) {
          return (route: ReasoningRoute.refused, field: 'reasoning.effort');
        }
        if (tried.contains(LearnedBehaviour.effortNone)) {
          return (
            route: ReasoningRoute.offToDefault,
            field: 'reasoning.effort',
          );
        }
        return (route: ReasoningRoute.protocolField, field: 'reasoning.effort');
    }
  }
}
