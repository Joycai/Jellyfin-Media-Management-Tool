import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ai_service_profile.dart';
import '../utils/ids.dart';
import 'ai/ai_provider.dart';

class SearchSite {
  String name;
  String url;

  SearchSite({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory SearchSite.fromJson(Map<String, dynamic> json) => SearchSite(
        name: json['name'],
        url: json['url'],
      );
}

class SettingsService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  int _lastSearchSiteIndex = 0;
  List<AiServiceProfile> _aiServices = [];
  String? _activeAiServiceId;
  List<String> _favorites = [];
  List<String> _recent = [];

  // Appearance + behavior, surfaced on the Settings screen.
  double _glassIntensity = 70; // 0–100
  int? _accentColor; // ARGB int; null = default theme accent
  bool _autoConnectAi = true;
  bool _alwaysShowPreview = true;
  bool _lowConfidenceSuggestOnly = false;
  bool _onboardingSeen = false;
  List<SearchSite> _searchSites = [
    SearchSite(name: 'TMDB', url: 'https://www.themoviedb.org/search?language={lang}&query={keyword}'),
    SearchSite(name: 'AniDB', url: 'https://anidb.net/search/anime/?adb.search={keyword}&do.search=1'),
    SearchSite(name: 'TVDB', url: 'https://www.thetvdb.com/search?query={keyword}'),
  ];

  static const int _maxRecent = 8;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  List<SearchSite> get searchSites => _searchSites;
  int get lastSearchSiteIndex => _lastSearchSiteIndex;
  List<AiServiceProfile> get aiServices => List.unmodifiable(_aiServices);
  String? get activeAiServiceId => _activeAiServiceId;

  /// The active profile, falling back to the first configured one.
  AiServiceProfile? get activeAiService {
    if (_aiServices.isEmpty) return null;
    return _aiServices.firstWhere(
      (s) => s.id == _activeAiServiceId,
      orElse: () => _aiServices.first,
    );
  }

  /// Runtime config for the active profile (consumed by [AiService]).
  AiConfig get aiConfig => activeAiService?.toAiConfig() ?? AiConfig.empty;
  List<String> get favorites => List.unmodifiable(_favorites);
  List<String> get recent => List.unmodifiable(_recent);
  double get glassIntensity => _glassIntensity;
  int? get accentColor => _accentColor;
  bool get autoConnectAi => _autoConnectAi;
  bool get alwaysShowPreview => _alwaysShowPreview;
  bool get lowConfidenceSuggestOnly => _lowConfidenceSuggestOnly;
  bool get onboardingSeen => _onboardingSeen;

  Future<Directory> get _configDir async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> get _configFile async => File(p.join((await _configDir).path, 'config.json'));
  Future<File> get _sitesFile async => File(p.join((await _configDir).path, 'sites.json'));

  Future<void> init() async {
    try {
      final configFile = await _configFile;
      if (await configFile.exists()) {
        final String content = await configFile.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);
          if (data['theme_mode'] is int) {
            _themeMode = ThemeMode.values[data['theme_mode']];
          }
          if (data['locale'] is String) {
            _locale = Locale(data['locale']);
          }
          if (data['last_search_site_index'] is int) {
            _lastSearchSiteIndex = data['last_search_site_index'];
          }
          if (data['ai_services'] is List) {
            _aiServices = (data['ai_services'] as List)
                .whereType<Map<String, dynamic>>()
                .map(AiServiceProfile.fromJson)
                .toList();
            _activeAiServiceId = data['active_ai_service'] as String?;
          } else if (data['ai'] is Map<String, dynamic>) {
            // Migrate the previous single-endpoint config into one profile.
            final cfg = AiConfig.fromJson(data['ai']);
            final migrated = AiServiceProfile(
              id: newId(),
              name: cfg.provider == AiProviderType.googleGenAi ? 'Google GenAI' : 'OpenAI',
              provider: cfg.provider,
              endpoint: cfg.endpoint,
              apiKey: cfg.apiKey,
              model: cfg.model,
              temperature: cfg.temperature,
            );
            _aiServices = [migrated];
            _activeAiServiceId = migrated.id;
          }
          if (data['glass_intensity'] is num) {
            _glassIntensity = (data['glass_intensity'] as num).toDouble().clamp(0, 100);
          }
          if (data['accent_color'] is int) {
            _accentColor = data['accent_color'] as int;
          }
          if (data['auto_connect_ai'] is bool) {
            _autoConnectAi = data['auto_connect_ai'] as bool;
          }
          if (data['always_show_preview'] is bool) {
            _alwaysShowPreview = data['always_show_preview'] as bool;
          }
          if (data['low_confidence_suggest_only'] is bool) {
            _lowConfidenceSuggestOnly = data['low_confidence_suggest_only'] as bool;
          }
          if (data['onboarding_seen'] is bool) {
            _onboardingSeen = data['onboarding_seen'] as bool;
          }
          if (data['favorites'] is List) {
            _favorites = List<String>.from(data['favorites']);
          }
          if (data['recent'] is List) {
            _recent = List<String>.from(data['recent']);
          }
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

  Future<void> _saveConfig() async {
    try {
      final file = await _configFile;
      final Map<String, dynamic> data = {
        'theme_mode': _themeMode.index,
        'locale': _locale?.languageCode,
        'last_search_site_index': _lastSearchSiteIndex,
        'ai_services': _aiServices.map((s) => s.toJson()).toList(),
        'active_ai_service': _activeAiServiceId,
        'glass_intensity': _glassIntensity,
        'accent_color': _accentColor,
        'auto_connect_ai': _autoConnectAi,
        'always_show_preview': _alwaysShowPreview,
        'low_confidence_suggest_only': _lowConfidenceSuggestOnly,
        'onboarding_seen': _onboardingSeen,
        'favorites': _favorites,
        'recent': _recent,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving config: $e');
    }
  }

  Future<void> _saveSites() async {
    try {
      final file = await _sitesFile;
      await file.writeAsString(jsonEncode(_searchSites.map((s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving sites: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setLastSearchSiteIndex(int index) async {
    _lastSearchSiteIndex = index;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setGlassIntensity(double v) async {
    _glassIntensity = v.clamp(0, 100);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setAccentColor(int? argb) async {
    _accentColor = argb;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setAutoConnectAi(bool v) async {
    _autoConnectAi = v;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setAlwaysShowPreview(bool v) async {
    _alwaysShowPreview = v;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setLowConfidenceSuggestOnly(bool v) async {
    _lowConfidenceSuggestOnly = v;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setOnboardingSeen(bool v) async {
    _onboardingSeen = v;
    await _saveConfig();
    notifyListeners();
  }

  /// Adds a profile and makes it active. Returns the added profile.
  Future<AiServiceProfile> addAiService(AiServiceProfile profile) async {
    _aiServices = [..._aiServices, profile];
    _activeAiServiceId = profile.id;
    await _saveConfig();
    notifyListeners();
    return profile;
  }

  /// Replaces a profile in place (matched by id).
  Future<void> updateAiService(AiServiceProfile profile) async {
    final idx = _aiServices.indexWhere((s) => s.id == profile.id);
    if (idx < 0) return;
    _aiServices = [..._aiServices]..[idx] = profile;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> deleteAiService(String id) async {
    _aiServices = _aiServices.where((s) => s.id != id).toList();
    if (_activeAiServiceId == id) {
      _activeAiServiceId = _aiServices.isNotEmpty ? _aiServices.first.id : null;
    }
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setActiveAiService(String id) async {
    if (_aiServices.every((s) => s.id != id)) return;
    _activeAiServiceId = id;
    await _saveConfig();
    notifyListeners();
  }

  bool isFavorite(String path) => _favorites.contains(path);

  Future<void> toggleFavorite(String path) async {
    if (_favorites.contains(path)) {
      _favorites.remove(path);
    } else {
      _favorites.add(path);
    }
    await _saveConfig();
    notifyListeners();
  }

  /// Records [path] as the most recently opened folder, de-duplicated and
  /// capped at [_maxRecent].
  Future<void> pushRecent(String path) async {
    _recent.remove(path);
    _recent.insert(0, path);
    if (_recent.length > _maxRecent) {
      _recent = _recent.sublist(0, _maxRecent);
    }
    await _saveConfig();
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
