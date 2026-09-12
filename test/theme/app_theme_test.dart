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
          a.extension<AppTokens>()!.blurPanel,
          greaterThan(b.extension<AppTokens>()!.blurPanel),
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
        again.extension<AppTokens>()!.blurPanel,
        first.extension<AppTokens>()!.blurPanel,
      );
    });
  });

  group('glass intensity 0 is the reduced-effects step', () {
    test('is part of the memo key', () {
      // The whole step is silent if it is not: MyApp asks for the theme on
      // every settings notification, so the first call after startup would
      // seed the slot and every later one would serve that same theme back.
      final normal = AppTheme.light(glassIntensity: 70);
      final reduced = AppTheme.light(glassIntensity: 0);
      expect(identical(normal, reduced), isFalse);
      expect(
        identical(AppTheme.light(glassIntensity: 70), normal),
        isFalse,
        reason: 'evicted',
      );
    });

    test('zeroes the blur and flattens the fills in both brightnesses', () {
      for (final tokens in [
        AppTheme.light(glassIntensity: 0).extension<AppTokens>()!,
        AppTheme.dark(glassIntensity: 0).extension<AppTokens>()!,
      ]) {
        expect(tokens.reduceEffects, isTrue);
        expect(tokens.blurTopBar, 0);
        expect(tokens.blurPanel, 0);
        expect(tokens.blurDialog, 0);
        // Opaque, so a panel reads as a panel without a blur behind it — and
        // so GlassSurface's own fill check would drop the filter regardless.
        expect(tokens.panelFill.a, 1.0);
        expect(tokens.topBarFill.a, 1.0);
        expect(tokens.controlFill.a, 1.0);
      }
    });

    test('the opaque swap is tied to 0, not to a separate flag', () {
      // The bug this replaced: intensity 0 dropped the blur but kept the
      // translucent fills, which is exactly the ~2:1 contrast state the old
      // "performance mode" toggle existed to prevent — and it was reachable
      // without ever touching that toggle.
      final barelyOn = AppTheme.dark(glassIntensity: 1).extension<AppTokens>()!;
      expect(barelyOn.reduceEffects, isFalse);
      expect(barelyOn.blurPanel, greaterThan(0));
      expect(barelyOn.panelFill.a, lessThan(1.0));
    });

    test('leaves the normal theme frosted', () {
      final tokens = AppTheme.dark().extension<AppTokens>()!;
      expect(tokens.reduceEffects, isFalse);
      expect(tokens.blurPanel, greaterThan(0));
      expect(tokens.panelFill.a, lessThan(1.0));
    });
  });
}
