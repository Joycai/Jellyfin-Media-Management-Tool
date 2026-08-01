import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/shortcuts/app_shortcuts.dart';

/// A value signature for an activator.
///
/// `SingleActivator` has no `operator ==`, so two separately-built instances of
/// the same combination are distinct map keys — tests must compare by value,
/// never by looking a reconstructed activator up in the bindings map. (The
/// runtime is unaffected: `CallbackShortcuts` walks `bindings.keys` calling
/// `accepts`, it never does a keyed lookup.)
String _sig(SingleActivator a) =>
    '${a.trigger.keyId}|${a.control}|${a.alt}|${a.shift}|${a.meta}';

/// The bindings map re-keyed by [_sig] so tests can address entries by value.
Map<String, VoidCallback> _bySignature(
  Map<ShortcutActivator, VoidCallback> bindings,
) => {
  for (final e in bindings.entries) _sig(e.key as SingleActivator): e.value,
};

void main() {
  // buildShortcutBindings wraps skipWhileTyping shortcuts in a guard that
  // reads FocusManager.instance, which needs a live binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('appShortcuts table', () {
    test('every id appears exactly once', () {
      for (final mac in [true, false]) {
        final ids = appShortcuts(isMac: mac).map((s) => s.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'isMac=$mac');
        expect(ids.toSet(), AppShortcutId.values.toSet(), reason: 'isMac=$mac');
      }
    });

    test('no two shortcuts claim the same key combination', () {
      // The point of the whole file: a duplicate activator would silently make
      // one of the two shortcuts unreachable, since bindings is a Map.
      for (final mac in [true, false]) {
        final seen = <String, AppShortcutId>{};
        for (final shortcut in appShortcuts(isMac: mac)) {
          for (final activator in shortcut.activators) {
            final sig = _sig(activator);
            expect(
              seen[sig],
              isNull,
              reason:
                  'isMac=$mac: ${shortcut.id} collides with ${seen[sig]} '
                  'on ${formatActivator(activator, isMac: mac)}',
            );
            seen[sig] = shortcut.id;
          }
        }
      }
    });

    test('every shortcut has at least one activator', () {
      for (final mac in [true, false]) {
        for (final shortcut in appShortcuts(isMac: mac)) {
          expect(shortcut.activators, isNotEmpty, reason: '${shortcut.id}');
        }
      }
    });

    test('the primary modifier is meta on macOS and control elsewhere', () {
      SingleActivator primaryOf(AppShortcutId id, bool mac) =>
          appShortcuts(isMac: mac).firstWhere((s) => s.id == id).primary;

      final onMac = primaryOf(AppShortcutId.focusSearch, true);
      expect(onMac.meta, isTrue);
      expect(onMac.control, isFalse);

      final elsewhere = primaryOf(AppShortcutId.focusSearch, false);
      expect(elsewhere.control, isTrue);
      expect(elsewhere.meta, isFalse);
    });

    test('history avoids bare Cmd+H, which macOS swallows as Hide', () {
      final history = appShortcuts(
        isMac: true,
      ).firstWhere((s) => s.id == AppShortcutId.history);
      for (final activator in history.activators) {
        final bare =
            activator.trigger == LogicalKeyboardKey.keyH &&
            activator.meta &&
            !activator.shift &&
            !activator.alt &&
            !activator.control;
        expect(bare, isFalse);
      }
    });

    test('plain Backspace is never bound — the search field needs it', () {
      for (final mac in [true, false]) {
        for (final shortcut in appShortcuts(isMac: mac)) {
          for (final a in shortcut.activators) {
            if (a.trigger != LogicalKeyboardKey.backspace) continue;
            expect(
              a.control || a.alt || a.shift || a.meta,
              isTrue,
              reason: 'isMac=$mac: ${shortcut.id} binds unmodified Backspace',
            );
          }
        }
      }
    });

    test(
      'shortcuts that collide with text editing stand down while typing',
      () {
        final byId = {for (final s in appShortcuts(isMac: false)) s.id: s};
        // Ctrl+A / Delete / Alt+↑ all mean something else inside a text field.
        expect(byId[AppShortcutId.selectAll]!.skipWhileTyping, isTrue);
        expect(byId[AppShortcutId.delete]!.skipWhileTyping, isTrue);
        expect(byId[AppShortcutId.parentFolder]!.skipWhileTyping, isTrue);
        // Focus-search must keep working from inside the search box.
        expect(byId[AppShortcutId.focusSearch]!.skipWhileTyping, isFalse);
      },
    );
  });

  group('buildShortcutBindings', () {
    test('binds every activator of a handled id, not just the primary', () {
      var calls = 0;
      final bound = _bySignature(
        buildShortcutBindings({
          AppShortcutId.refresh: () => calls++,
        }, isMac: false),
      );

      final refresh = appShortcuts(
        isMac: false,
      ).firstWhere((s) => s.id == AppShortcutId.refresh);
      expect(
        refresh.activators.length,
        greaterThan(1),
        reason: 'F5 and Ctrl+R',
      );

      for (final activator in refresh.activators) {
        final callback = bound[_sig(activator)];
        expect(callback, isNotNull, reason: formatActivator(activator));
        callback!();
      }
      expect(calls, refresh.activators.length);
    });

    test('leaves ids without a handler unbound', () {
      final bound = _bySignature(
        buildShortcutBindings({AppShortcutId.refresh: () {}}, isMac: false),
      );

      final settings = appShortcuts(
        isMac: false,
      ).firstWhere((s) => s.id == AppShortcutId.settings);
      expect(bound[_sig(settings.primary)], isNull);
      expect(bound, hasLength(2)); // only refresh's F5 + Ctrl+R
    });

    test('an empty handler map produces no bindings', () {
      expect(buildShortcutBindings({}, isMac: false), isEmpty);
    });
  });

  group('formatActivator', () {
    test('uses Ctrl+K notation off macOS', () {
      expect(
        formatActivator(
          const SingleActivator(LogicalKeyboardKey.keyK, control: true),
          isMac: false,
        ),
        'Ctrl+K',
      );
    });

    test('uses glyph notation on macOS', () {
      expect(
        formatActivator(
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true),
          isMac: true,
        ),
        '⌘K',
      );
    });

    test('orders macOS modifiers as ⌃⌥⇧⌘', () {
      expect(
        formatActivator(
          const SingleActivator(
            LogicalKeyboardKey.keyH,
            control: true,
            alt: true,
            shift: true,
            meta: true,
          ),
          isMac: true,
        ),
        '⌃⌥⇧⌘H',
      );
    });

    test('spells out named keys', () {
      expect(
        formatActivator(
          const SingleActivator(LogicalKeyboardKey.escape),
          isMac: false,
        ),
        'Esc',
      );
      expect(
        formatActivator(
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true),
          isMac: false,
        ),
        'Alt+↑',
      );
      expect(
        formatActivator(
          const SingleActivator(LogicalKeyboardKey.f5),
          isMac: false,
        ),
        'F5',
      );
      expect(
        formatActivator(
          const SingleActivator(LogicalKeyboardKey.comma, control: true),
          isMac: false,
        ),
        'Ctrl+,',
      );
    });

    test('shortcutLabel renders the primary activator of an id', () {
      expect(shortcutLabel(AppShortcutId.focusSearch, isMac: false), 'Ctrl+K');
      expect(shortcutLabel(AppShortcutId.focusSearch, isMac: true), '⌘K');
    });
  });
}
