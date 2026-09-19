import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/file_browser/media_columns.dart';
import 'ai/api_log.dart';

class SearchSite {
  String name;
  String url;

  SearchSite({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory SearchSite.fromJson(Map<String, dynamic> json) =>
      SearchSite(name: json['name'], url: json['url']);
}

/// User preferences that aren't AI profiles or library nav state: theme,
/// locale, glass intensity, accent color, behavior toggles, onboarding,
/// search sites. AI profiles live in [AiProfilesService] and favorites /
/// recent live in [LibraryNavService] (when introduced) — split so each
/// concern writes to its own file and a slider drag doesn't rewrite the
/// AI keys (or vice versa).
class SettingsService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  int _lastSearchSiteIndex = 0;
  List<String> _favorites = [];
  List<String> _recent = [];

  // Appearance + behavior, surfaced on the Settings screen.
  double _glassIntensity = 70; // 0–100

  /// Render the glass blur from a pre-baked image instead of a live
  /// `BackdropFilter`. Defaults on: on the reference machine it is worth
  /// ~46ms/frame maximized at 4K and the panels look the same either way.
  /// Independent of [glassIntensity] — that decides how much blur, this
  /// decides how it is computed, and 0 means there is none to compute.
  bool _bakedGlass = true;
  int? _accentColor; // ARGB int; null = default theme accent
  List<int> _accentRecents = [];
  bool _showVideoThumbnails = true;
  bool _apiLogEnabled = false;
  bool _onboardingSeen = false;

  /// UI font id: 'system' | 'harmony' | 'misans' (see FontService).
  String _fontChoice = 'system';
  List<SearchSite> _searchSites = [
    SearchSite(
      name: 'TMDB',
      url: 'https://www.themoviedb.org/search?language={lang}&query={keyword}',
    ),
    SearchSite(
      name: 'AniDB',
      url: 'https://anidb.net/search/anime/?adb.search={keyword}&do.search=1',
    ),
    SearchSite(
      name: 'TVDB',
      url: 'https://www.thetvdb.com/search?query={keyword}',
    ),
  ];

  /// 最近访问保留的条数。设置页的说明文案引用它，免得两处各写一个数字。
  static const int maxRecent = 8;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  List<SearchSite> get searchSites => _searchSites;
  int get lastSearchSiteIndex => _lastSearchSiteIndex;
  List<String> get favorites => List.unmodifiable(_favorites);
  List<String> get recent => List.unmodifiable(_recent);
  double get glassIntensity => _glassIntensity;
  bool get bakedGlass => _bakedGlass;
  int? get accentColor => _accentColor;

  /// 取色浮层的「最近使用」：应用过的自定义强调色，先进先出，最多
  /// [maxAccentRecents] 个（6.2）。预设色不入列 —— 它们本来就一直在那儿。
  List<int> get accentRecents => List.unmodifiable(_accentRecents);
  static const int maxAccentRecents = 6;
  bool get showVideoThumbnails => _showVideoThumbnails;

  /// Whether every AI request is written to the API log — see [ApiLog].
  bool get apiLogEnabled => _apiLogEnabled;
  bool get onboardingSeen => _onboardingSeen;
  String get fontChoice => _fontChoice;

  /// Where everything this app persists lives, once something has asked for it
  /// (`init()` does, on the first frame). Null before that: the privacy page
  /// shows a placeholder rather than blocking a frame on a disk call, and this
  /// is a label — nothing reads or writes through it.
  String? get configPath => _configPath;
  String? _configPath;

  Future<Directory> get _configDir async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _configPath = directory.path;
    return directory;
  }

  Future<File> get _configFile async =>
      File(p.join((await _configDir).path, 'config.json'));
  Future<File> get _sitesFile async =>
      File(p.join((await _configDir).path, 'sites.json'));

  /// Parses a BCP 47 language tag back into a [Locale], telling a 4-letter
  /// script subtag (`zh-Hant`) apart from a 2-letter/3-digit region (`zh-TW`,
  /// `es-419`) — splitting on `-` and calling position 1 the country would
  /// file `Hant` as a country code.
  static Locale parseLocaleTag(String tag) {
    final parts = tag.split('-');
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4) {
        script ??= part;
      } else if (part.length == 2 || part.length == 3) {
        country ??= part;
      }
    }
    return Locale.fromSubtags(
      languageCode: parts.first,
      scriptCode: script,
      countryCode: country,
    );
  }

  /// Fold a decoded `config.json` into this service.
  ///
  /// Split out of [init] so the migrations in here are testable without a
  /// filesystem — there is real branching now, not just field copying.
  @visibleForTesting
  void applyConfig(Map<String, dynamic> data) {
    if (data['theme_mode'] is int) {
      _themeMode = ThemeMode.values[data['theme_mode']];
    }
    if (data['locale'] is String) {
      _locale = parseLocaleTag(data['locale'] as String);
    }
    if (data['last_search_site_index'] is int) {
      _lastSearchSiteIndex = data['last_search_site_index'];
    }
    if (data['glass_intensity'] is num) {
      _glassIntensity = (data['glass_intensity'] as num).toDouble().clamp(
        0,
        100,
      );
    }
    if (data['accent_color'] is int) {
      _accentColor = data['accent_color'] as int;
    }
    if (data['accent_recents'] is List) {
      _accentRecents = [
        for (final v in data['accent_recents'] as List)
          if (v is int) v,
      ];
    }
    if (data['show_video_thumbnails'] is bool) {
      _showVideoThumbnails = data['show_video_thumbnails'] as bool;
    }
    if (data['api_log_enabled'] is bool) {
      _apiLogEnabled = data['api_log_enabled'] as bool;
      ApiLog.instance.enabled = _apiLogEnabled;
    }
    if (data['baked_glass'] is bool) {
      _bakedGlass = data['baked_glass'] as bool;
    }
    // 迁移：从前「性能模式」是一个独立开关，现在它就是玻璃强度 0。
    // 开着它的人要的是「别做毛玻璃」，那正是 0 这一档的意思；键不再写回，
    // 下次保存就消失了。
    if (data['performance_mode'] == true) {
      _glassIntensity = 0;
    }
    if (data['onboarding_seen'] is bool) {
      _onboardingSeen = data['onboarding_seen'] as bool;
    }
    if (data['font_choice'] is String) {
      _fontChoice = data['font_choice'] as String;
    }
    if (data['favorites'] is List) {
      _favorites = List<String>.from(data['favorites']);
    }
    if (data['recent'] is List) {
      _recent = List<String>.from(data['recent']);
    }
    if (data['column_weights'] is Map) {
      final raw = data['column_weights'] as Map;
      _columnWeights = {
        for (final column in MediaColumn.values)
          if (raw[column.name] is num)
            column: (raw[column.name] as num).toDouble(),
      };
      _sanitizedColumnWeights = null;
    }
  }

  Future<void> init() async {
    try {
      final configFile = await _configFile;
      if (await configFile.exists()) {
        final String content = await configFile.readAsString();
        if (content.isNotEmpty) {
          applyConfig(jsonDecode(content) as Map<String, dynamic>);
        }
      }

      final sitesFile = await _sitesFile;
      if (await sitesFile.exists()) {
        final String content = await sitesFile.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> data = jsonDecode(content);
          _searchSites = data.map((item) => SearchSite.fromJson(item)).toList();
        }
      }
    } catch (e) {
      debugPrint('Error loading config: $e');
    }
    notifyListeners();
  }

  /// Debounce window for [_scheduleSave]. Long enough to coalesce a slider
  /// drag (60+ ticks/sec) into a single disk write; short enough that the
  /// user can quit the app and trust their change persisted.
  static const _saveDebounce = Duration(milliseconds: 250);

  Timer? _saveTimer;

  /// Coalesces back-to-back setter calls into a single [_saveConfig] write.
  /// Used by every setter that mutates the JSON-backed slice; the
  /// search-sites file has its own [_saveSites].
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      _saveTimer = null;
      unawaited(_saveConfig());
    });
  }

  Future<void> _saveConfig() async {
    try {
      final file = await _configFile;
      final Map<String, dynamic> data = {
        'theme_mode': _themeMode.index,
        'locale': _locale?.toLanguageTag(),
        'last_search_site_index': _lastSearchSiteIndex,
        'glass_intensity': _glassIntensity,
        'accent_color': _accentColor,
        'accent_recents': _accentRecents,
        'show_video_thumbnails': _showVideoThumbnails,
        'api_log_enabled': _apiLogEnabled,
        'baked_glass': _bakedGlass,
        'onboarding_seen': _onboardingSeen,
        'font_choice': _fontChoice,
        'favorites': _favorites,
        'recent': _recent,
        'column_weights': {
          for (final e in _columnWeights.entries) e.key.name: e.value,
        },
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving config: $e');
    }
  }

  @override
  void dispose() {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      unawaited(_saveConfig());
    }
    super.dispose();
  }

  Future<void> _saveSites() async {
    try {
      final file = await _sitesFile;
      await file.writeAsString(
        jsonEncode(_searchSites.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving sites: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setLastSearchSiteIndex(int index) async {
    _lastSearchSiteIndex = index;
    _scheduleSave();
    notifyListeners();
  }

  /// 玻璃强度 0–100。
  ///
  /// **0 不只是「模糊半径为零」** —— 它是这个 app 唯一的降级档：不建
  /// `BackdropFilter`，并且把玻璃底换成不透明实色、发丝线加重、大投影压平，
  /// 否则没有模糊衬托的半透明底会掉到约 2:1 对比度。推导发生在
  /// `AppTokens.build`，这里只存数。
  Future<void> setGlassIntensity(double v) async {
    _glassIntensity = v.clamp(0, 100);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setBakedGlass(bool v) async {
    _bakedGlass = v;
    _scheduleSave();
    notifyListeners();
  }

  /// File-table column widths, as weights. See [MediaColumnLayout] for why
  /// weights rather than pixels.
  Map<MediaColumn, double> _columnWeights = {};

  /// Memoized [MediaColumnLayout.sanitize] of [_columnWeights].
  ///
  /// The getter used to sanitize on every read, handing back a fresh map each
  /// time. `context.select` compares with `==`, and two equal-but-distinct maps
  /// are not `==`, so selecting on this rebuilt the table on every unrelated
  /// settings change. Cached, the instance is stable until the weights
  /// actually move.
  Map<MediaColumn, double>? _sanitizedColumnWeights;
  Map<MediaColumn, double> get columnWeights =>
      _sanitizedColumnWeights ??= MediaColumnLayout.sanitize(_columnWeights);

  /// Called on every drag frame, so it leans on the same 250ms debounce as the
  /// glass slider rather than writing the file per pixel.
  void setColumnWeights(Map<MediaColumn, double> weights) {
    _columnWeights = Map.of(weights);
    _sanitizedColumnWeights = null;
    _scheduleSave();
    notifyListeners();
  }

  void resetColumnWeights() {
    _columnWeights = {};
    _sanitizedColumnWeights = null;
    _scheduleSave();
    notifyListeners();
  }

  /// 换强调色。
  ///
  /// [remember] 只在用户**确认**取色时为真：拖动取色器会一路调用这个方法做实时
  /// 预览，把每一个中间色都记进「最近使用」，六个格子在一次拖动里就被同一条色相
  /// 上的邻居填满了。
  Future<void> setAccentColor(int? argb, {bool remember = false}) async {
    _accentColor = argb;
    if (remember && argb != null) {
      _accentRecents.remove(argb);
      _accentRecents.insert(0, argb);
      if (_accentRecents.length > maxAccentRecents) {
        _accentRecents = _accentRecents.sublist(0, maxAccentRecents);
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setShowVideoThumbnails(bool v) async {
    _showVideoThumbnails = v;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setApiLogEnabled(bool v) async {
    _apiLogEnabled = v;
    ApiLog.instance.enabled = v;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setFontChoice(String id) async {
    _fontChoice = id;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setOnboardingSeen(bool v) async {
    _onboardingSeen = v;
    _scheduleSave();
    notifyListeners();
  }

  bool isFavorite(String path) => _favorites.contains(path);

  Future<void> toggleFavorite(String path) async {
    if (_favorites.contains(path)) {
      _favorites.remove(path);
    } else {
      _favorites.add(path);
    }
    _scheduleSave();
    notifyListeners();
  }

  /// Records [path] as the most recently opened folder, de-duplicated and
  /// capped at [maxRecent].
  Future<void> pushRecent(String path) async {
    _recent.remove(path);
    _recent.insert(0, path);
    if (_recent.length > maxRecent) {
      _recent = _recent.sublist(0, maxRecent);
    }
    _scheduleSave();
    notifyListeners();
  }

  Future<void> updateSearchSites(List<SearchSite> sites) async {
    _searchSites = sites;
    await _saveSites();
    notifyListeners();
  }

  Future<void> openConfigFolder() async {
    final dir = await _configDir;
    final uri = Uri.file(dir.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
