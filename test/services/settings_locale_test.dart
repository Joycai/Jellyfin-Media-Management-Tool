import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';

void main() {
  group('SettingsService.parseLocaleTag', () {
    test('a bare language round-trips', () {
      expect(SettingsService.parseLocaleTag('en'), const Locale('en'));
    });

    test('language-country round-trips', () {
      expect(
        SettingsService.parseLocaleTag('zh-TW'),
        const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
      );
    });

    test('a script subtag is not mistaken for a country', () {
      expect(
        SettingsService.parseLocaleTag('zh-Hant'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    });

    test('language-script-country keeps all three', () {
      expect(
        SettingsService.parseLocaleTag('zh-Hant-TW'),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      );
    });

    test('a numeric UN M.49 region is a country, not a script', () {
      expect(
        SettingsService.parseLocaleTag('es-419'),
        const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
      );
    });

    test('every persisted form survives a save/load round trip', () {
      for (final tag in ['en', 'zh', 'zh-Hant', 'zh-Hant-TW', 'es-419']) {
        final locale = SettingsService.parseLocaleTag(tag);
        expect(locale.toLanguageTag(), tag);
      }
    });
  });
}
