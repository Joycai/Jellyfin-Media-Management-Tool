import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SettingsService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;

  Future<File> get _configFile async {
    // getApplicationSupportDirectory is widely supported and resolves to:
    // Windows: AppData\Roaming
    // macOS: ~/Library/Application Support
    // Linux: ~/.local/share
    final directory = await getApplicationSupportDirectory();
    
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    return File(p.join(directory.path, 'config.json'));
  }

  Future<void> init() async {
    try {
      final file = await _configFile;
      if (await file.exists()) {
        final String content = await file.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);

          if (data.containsKey('theme_mode')) {
            _themeMode = ThemeMode.values[data['theme_mode']];
          }

          if (data.containsKey('locale')) {
            _locale = Locale(data['locale']);
          }
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
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving config: $e');
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
}
