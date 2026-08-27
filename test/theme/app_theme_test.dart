import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';

void main() {
  group('ThemeData is memoized per brightness', () {
    test('identical inputs hand back the identical instance', () {
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    });

    test('light and dark do not evict each other', () {
      // MyApp.build asks for both on every rebuild, so a single shared slot
      // would miss every time and the cache would do nothing at all.
      final light = AppTheme.light();
      final dark = AppTheme.dark();
      expect(identical(AppTheme.light(), light), isTrue);
      expect(identical(AppTheme.dark(), dark), isTrue);
      expect(identical(AppTheme.light(), light), isTrue);
    });

    test(
      'a changed input builds a new theme rather than serving the old one',
      () {
        final a = AppTheme.light(glassIntensity: 70);
        final b = AppTheme.light(glassIntensity: 20);
        expect(identical(a, b), isFalse);
        expect(
          a.extension<GlassTheme>()!.blurSigma,
          greaterThan(b.extension<GlassTheme>()!.blurSigma),
        );

        final accented = AppTheme.light(accent: const Color(0xFFEE7B3A));
        expect(identical(accented, AppTheme.light()), isFalse);
        expect(accented.colorScheme.primary, const Color(0xFFEE7B3A));

        expect(
          identical(AppTheme.light(fontFamily: 'MiSans'), AppTheme.light()),
          isFalse,
        );
      },
    );

    test('a repeat of an earlier input still rebuilds once evicted', () {
      final first = AppTheme.light(glassIntensity: 70);
      AppTheme.light(glassIntensity: 20);
      final again = AppTheme.light(glassIntensity: 70);
      // Same values, so it must be equivalent — just not the same object, the
      // one slot having moved on.
      expect(identical(again, first), isFalse);
      expect(
        again.extension<GlassTheme>()!.blurSigma,
        first.extension<GlassTheme>()!.blurSigma,
      );
    });
  });
}
