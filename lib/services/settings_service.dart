import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

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
  List<SearchSite> _searchSites = [
    SearchSite(name: 'TMDB', url: 'https://www.themoviedb.org/search?language={lang}&query={keyword}'),
    SearchSite(name: 'AniDB', url: 'https://anidb.net/search/anime/?adb.search={keyword}&do.search=1'),
    SearchSite(name: 'TVDB', url: 'https://www.thetvdb.com/search?query={keyword}'),
  ];

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  List<SearchSite> get searchSites => _searchSites;
  int get lastSearchSiteIndex => _lastSearchSiteIndex;

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
          if (data.containsKey('theme_mode')) {
            _themeMode = ThemeMode.values[data['theme_mode']];
          }
          if (data.containsKey('locale')) {
            _locale = Locale(data['locale']);
          }
          if (data.containsKey('last_search_site_index')) {
            _lastSearchSiteIndex = data['last_search_site_index'];
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
