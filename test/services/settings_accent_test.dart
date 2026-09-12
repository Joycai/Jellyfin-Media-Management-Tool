import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';

/// The accent picker previews live, by calling [SettingsService.setAccentColor]
/// on every drag tick. That makes "which of those calls counts as a choice" a
/// real question, and these pin the answer.
void main() {
  group('accent recents', () {
    test('a preview does not enter the list; applying does', () {
      final settings = SettingsService();

      // A drag across one hue would otherwise fill all six slots with
      // neighbours of the colour the user finally picked.
      settings.setAccentColor(0xFF112233);
      settings.setAccentColor(0xFF112244);
      expect(settings.accentRecents, isEmpty);

      settings.setAccentColor(0xFF112255, remember: true);
      expect(settings.accentRecents, [0xFF112255]);
    });

    test('newest first, no duplicates, capped', () {
      final settings = SettingsService();
      for (var i = 0; i < SettingsService.maxAccentRecents + 2; i++) {
        settings.setAccentColor(0xFF000000 + i, remember: true);
      }

      expect(settings.accentRecents.length, SettingsService.maxAccentRecents);
      // Most recent leads; the two oldest fell off the end.
      expect(settings.accentRecents.first, 0xFF000007);
      expect(settings.accentRecents.contains(0xFF000000), isFalse);

      // Re-picking an entry moves it to the front rather than adding a second.
      settings.setAccentColor(0xFF000004, remember: true);
      expect(settings.accentRecents.first, 0xFF000004);
      expect(settings.accentRecents.where((c) => c == 0xFF000004).length, 1);
    });

    test('restoring the default clears the accent without recording null', () {
      final settings = SettingsService();
      settings.setAccentColor(0xFF445566, remember: true);
      settings.setAccentColor(null, remember: true);

      expect(settings.accentColor, isNull);
      expect(settings.accentRecents, [0xFF445566]);
    });
  });
}
