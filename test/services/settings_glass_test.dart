import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';

/// The glass slider is now the *only* graphics control: its 0 stop is what
/// used to be a separate `performance_mode` toggle. These pin the migration
/// off that toggle, because getting it wrong is silent — the app would simply
/// come back frosted for someone who had explicitly turned the frost off.
void main() {
  group('glass intensity', () {
    test('a stored performance_mode migrates to intensity 0', () {
      final settings = SettingsService();
      settings.applyConfig({'glass_intensity': 70, 'performance_mode': true});

      // Whoever set that toggle asked for "no frosted glass". That is exactly
      // what 0 means now, so their choice survives the merge — even though the
      // config also carries the intensity they never touched.
      expect(settings.glassIntensity, 0);
    });

    test('performance_mode false leaves the slider alone', () {
      final settings = SettingsService();
      settings.applyConfig({'glass_intensity': 70, 'performance_mode': false});
      expect(settings.glassIntensity, 70);
    });

    test('a config without the legacy key is untouched', () {
      final settings = SettingsService();
      settings.applyConfig({'glass_intensity': 42});
      expect(settings.glassIntensity, 42);
    });

    test('the intensity is clamped to 0-100', () {
      final low = SettingsService()..applyConfig({'glass_intensity': -30});
      final high = SettingsService()..applyConfig({'glass_intensity': 900});
      expect(low.glassIntensity, 0);
      expect(high.glassIntensity, 100);
    });
  });

  group('baked glass', () {
    test('defaults on', () {
      // Every config written before this setting existed has no key for it,
      // and those users are the ones the default is for: it is worth ~46ms a
      // frame maximized at 4K and the panels look the same either way.
      final settings = SettingsService();
      expect(settings.bakedGlass, isTrue);
      settings.applyConfig({'glass_intensity': 70});
      expect(settings.bakedGlass, isTrue);
    });

    test('a stored choice is honoured in both directions', () {
      final off = SettingsService()..applyConfig({'baked_glass': false});
      final on = SettingsService()..applyConfig({'baked_glass': true});
      expect(off.bakedGlass, isFalse);
      expect(on.bakedGlass, isTrue);
    });

    test('it is independent of the intensity slider', () {
      // The two answer different questions — how much blur, and how to compute
      // it — so neither may quietly overwrite the other's stored value. What
      // reconciles them is AppTokens.build, which drops baking when there is
      // no blur to bake; see baked_glass_test.dart.
      final settings = SettingsService()
        ..applyConfig({'glass_intensity': 0, 'baked_glass': true});
      expect(settings.glassIntensity, 0);
      expect(settings.bakedGlass, isTrue);
    });
  });
}
