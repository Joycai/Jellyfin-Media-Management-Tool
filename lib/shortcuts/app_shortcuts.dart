/// Every keyboard shortcut in the app, defined once.
///
/// `HomeScreen` builds its `CallbackShortcuts` map from [appShortcuts] and the
/// Settings → Shortcuts page renders its table from the same list, so adding a
/// shortcut is a single entry here rather than three edits that drift apart.
///
/// Activators are platform-aware: the primary modifier is ⌘ on macOS and Ctrl
/// everywhere else, and [formatActivator] renders the matching notation.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Stable identity of a shortcut. Callers map these to callbacks; an id with no
/// handler simply isn't bound.
enum AppShortcutId {
  focusSearch,
  refresh,
  parentFolder,
  openFolder,
  selectAll,
  escape,
  rename,
  delete,
  organize,
  toggleFavorite,
  history,
  settings,
  sectionFiles,
  sectionLibrary,
  sectionTasks,
}

/// Section headers on the settings page, in display order.
enum AppShortcutGroup { navigation, selection, files, app }

class AppShortcut {
  final AppShortcutId id;
  final AppShortcutGroup group;

  /// Key combinations that trigger this shortcut. The first is the one shown
  /// in settings; the rest are accepted aliases.
  final List<SingleActivator> activators;

  /// Localized one-line description shown in settings.
  final String Function(AppLocalizations) describe;

  /// Suppress the shortcut while a text field has focus, so it can't steal a
  /// key the editor needs (Ctrl+A select-all, Delete, Alt+↑ line start …).
  /// Off for shortcuts that must work while typing, like focus-search.
  final bool skipWhileTyping;

  const AppShortcut({
    required this.id,
    required this.group,
    required this.activators,
    required this.describe,
    this.skipWhileTyping = false,
  });

  SingleActivator get primary => activators.first;
}

bool _isMacPlatform() => defaultTargetPlatform == TargetPlatform.macOS;

/// The full shortcut table. [isMac] is injectable for tests; it defaults to the
/// running platform.
List<AppShortcut> appShortcuts({bool? isMac}) {
  final mac = isMac ?? _isMacPlatform();

  // The primary modifier: ⌘ on macOS, Ctrl elsewhere.
  SingleActivator cmd(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
  }) => SingleActivator(key, meta: mac, control: !mac, shift: shift, alt: alt);

  return [
    // ── Navigation ──────────────────────────────────────────────────────────
    AppShortcut(
      id: AppShortcutId.focusSearch,
      group: AppShortcutGroup.navigation,
      // Deliberately not skipWhileTyping: re-focusing search from search is a
      // harmless no-op, and blocking it would make the shortcut feel flaky.
      activators: [cmd(LogicalKeyboardKey.keyK), cmd(LogicalKeyboardKey.keyF)],
      describe: (l) => l.shortcutSearch,
    ),
    AppShortcut(
      id: AppShortcutId.parentFolder,
      group: AppShortcutGroup.navigation,
      // Alt+↑ is the Explorer binding; ⌘↑ the Finder one. Plain Backspace is
      // deliberately NOT bound — the search field needs it.
      activators: [
        if (mac)
          const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true)
        else
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true),
      ],
      describe: (l) => l.shortcutParentFolder,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.openFolder,
      group: AppShortcutGroup.navigation,
      activators: [cmd(LogicalKeyboardKey.keyO)],
      describe: (l) => l.shortcutOpenFolder,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.refresh,
      group: AppShortcutGroup.navigation,
      activators: [
        const SingleActivator(LogicalKeyboardKey.f5),
        cmd(LogicalKeyboardKey.keyR),
      ],
      describe: (l) => l.shortcutRefresh,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.sectionFiles,
      group: AppShortcutGroup.navigation,
      activators: [cmd(LogicalKeyboardKey.digit1)],
      describe: (l) => l.shortcutSectionFiles,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.sectionLibrary,
      group: AppShortcutGroup.navigation,
      activators: [cmd(LogicalKeyboardKey.digit2)],
      describe: (l) => l.shortcutSectionLibrary,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.sectionTasks,
      group: AppShortcutGroup.navigation,
      activators: [cmd(LogicalKeyboardKey.digit3)],
      describe: (l) => l.shortcutSectionTasks,
      skipWhileTyping: true,
    ),

    // ── Selection ───────────────────────────────────────────────────────────
    AppShortcut(
      id: AppShortcutId.selectAll,
      group: AppShortcutGroup.selection,
      activators: [cmd(LogicalKeyboardKey.keyA)],
      describe: (l) => l.shortcutSelectAll,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.escape,
      group: AppShortcutGroup.selection,
      activators: [const SingleActivator(LogicalKeyboardKey.escape)],
      describe: (l) => l.shortcutEscape,
    ),

    // ── Files ───────────────────────────────────────────────────────────────
    AppShortcut(
      id: AppShortcutId.rename,
      group: AppShortcutGroup.files,
      activators: [const SingleActivator(LogicalKeyboardKey.f2)],
      describe: (l) => l.shortcutRename,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.delete,
      group: AppShortcutGroup.files,
      activators: [
        const SingleActivator(LogicalKeyboardKey.delete),
        if (mac)
          const SingleActivator(LogicalKeyboardKey.backspace, meta: true),
      ],
      describe: (l) => l.shortcutDelete,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.organize,
      group: AppShortcutGroup.files,
      activators: [cmd(LogicalKeyboardKey.enter)],
      describe: (l) => l.shortcutOrganize,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.toggleFavorite,
      group: AppShortcutGroup.files,
      activators: [cmd(LogicalKeyboardKey.keyD)],
      describe: (l) => l.shortcutToggleFavorite,
      skipWhileTyping: true,
    ),

    // ── App ─────────────────────────────────────────────────────────────────
    AppShortcut(
      id: AppShortcutId.history,
      group: AppShortcutGroup.app,
      // Shift is not decorative: bare ⌘H is "Hide application" at the macOS
      // level and never reaches the app, so the plain form would be a silently
      // dead shortcut on one of three platforms.
      activators: [cmd(LogicalKeyboardKey.keyH, shift: true)],
      describe: (l) => l.shortcutHistory,
      skipWhileTyping: true,
    ),
    AppShortcut(
      id: AppShortcutId.settings,
      group: AppShortcutGroup.app,
      activators: [cmd(LogicalKeyboardKey.comma)],
      describe: (l) => l.shortcutSettings,
      skipWhileTyping: true,
    ),
  ];
}

/// True when the focused widget is a text editor, so a shortcut marked
/// [AppShortcut.skipWhileTyping] should stand down.
///
/// Needed because focus dispatch reaches a `CallbackShortcuts` placed inside
/// the app *before* Flutter's own `DefaultTextEditingShortcuts` near the root —
/// without this guard, Ctrl+A in the search box would select files instead of
/// text.
bool isTextFieldFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  // A TextField's focus node belongs to a `Focus` widget *inside* EditableText's
  // own build, so the focused context is that Focus, not the EditableText —
  // checking only `context.widget` silently never matches.
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Builds the `CallbackShortcuts` map from [appShortcuts], wiring each id to
/// its handler. Ids absent from [handlers] are left unbound.
Map<ShortcutActivator, VoidCallback> buildShortcutBindings(
  Map<AppShortcutId, VoidCallback> handlers, {
  bool? isMac,
}) {
  final bindings = <ShortcutActivator, VoidCallback>{};
  for (final shortcut in appShortcuts(isMac: isMac)) {
    final handler = handlers[shortcut.id];
    if (handler == null) continue;
    final guarded = shortcut.skipWhileTyping
        ? () {
            if (isTextFieldFocused()) return;
            handler();
          }
        : handler;
    for (final activator in shortcut.activators) {
      bindings[activator] = guarded;
    }
  }
  return bindings;
}

// ── Display notation ────────────────────────────────────────────────────────

// Not const: LogicalKeyboardKey overrides ==, which const map keys may not.
final _macKeyLabels = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.enter: '↩',
  LogicalKeyboardKey.backspace: '⌫',
  LogicalKeyboardKey.delete: '⌦',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.comma: ',',
};

final _keyLabels = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Del',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.comma: ',',
};

String _keyLabel(LogicalKeyboardKey key, bool mac) {
  final override = mac ? _macKeyLabels[key] : _keyLabels[key];
  if (override != null) return override;
  final label = key.keyLabel;
  return label.isEmpty ? key.debugName ?? '?' : label;
}

/// Display notation of [id]'s primary activator — `⌘K` on macOS, `Ctrl+K`
/// elsewhere. For hint text and tooltips, so no call site hardcodes a glyph.
String shortcutLabel(AppShortcutId id, {bool? isMac}) => formatActivator(
  appShortcuts(isMac: isMac).firstWhere((s) => s.id == id).primary,
  isMac: isMac,
);

/// Renders [activator] the way the platform writes it: `⌘⇧H` on macOS,
/// `Ctrl+Shift+H` elsewhere.
String formatActivator(SingleActivator activator, {bool? isMac}) {
  final mac = isMac ?? _isMacPlatform();
  final parts = <String>[];
  // macOS orders modifiers ⌃⌥⇧⌘ by convention.
  if (activator.control) parts.add(mac ? '⌃' : 'Ctrl');
  if (activator.alt) parts.add(mac ? '⌥' : 'Alt');
  if (activator.shift) parts.add(mac ? '⇧' : 'Shift');
  if (activator.meta) parts.add(mac ? '⌘' : 'Win');
  parts.add(_keyLabel(activator.trigger, mac));
  return parts.join(mac ? '' : '+');
}
