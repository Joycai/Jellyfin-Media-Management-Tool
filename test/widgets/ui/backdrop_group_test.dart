import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/shell/app_shell.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/glass_surface.dart';

/// A glass pane is the cheapest thing that actually builds a `BackdropFilter`.
Widget _pane() => const AppGlassPane(child: SizedBox.expand());

/// Every test here is about the **live filter** path, so baking is off.
///
/// With it on, the shell panels draw a crop of a pre-blurred image and build
/// no `BackdropFilter` at all once the bake lands — which is the whole point
/// of it, and is pinned in `baked_glass_test.dart`. Grouping still matters
/// underneath: it is what the app falls back to when the user turns baking
/// off, during the first frames before the first bake, and for every dialog
/// and popover, which are never baked.
Future<void> _pumpShell(WidgetTester tester, {Widget? body}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(bakedGlass: false),
        home: AppShell(
          titleBar: SizedBox(height: 48, child: _pane()),
          body: body ?? _pane(),
          statusBar: SizedBox(height: 28, child: _pane()),
        ),
      ),
    );

List<BackdropKey?> _keys(WidgetTester tester) => tester
    .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
    .map((r) => r.backdropKey)
    .toList();

void main() {
  testWidgets('the shell chrome shares one backdrop snapshot', (tester) async {
    // Four co-planar, non-overlapping filters each taking their own full-size
    // snapshot of the render target is the single most expensive avoidable
    // thing in this app: measured 80.4ms -> 64.6ms maximized at 4K just by
    // sharing one. They can share precisely because they do not overlap.
    await _pumpShell(tester);
    final keys = _keys(tester);
    expect(keys, hasLength(3));
    expect(keys, everyElement(isNotNull));
    expect(
      keys.toSet(),
      hasLength(1),
      reason: 'all shell surfaces must land in the same group',
    );
  });

  testWidgets('a dialog above the shell snapshots on its own', (tester) async {
    // This is the constraint that decides the whole design. Filters that
    // OVERLAP must not share a key, or the overlapping region looks as if only
    // one filter ran. A dialog sits on top of the panels and has to blur the
    // panels themselves — so it must not join the shell's group.
    //
    // Nothing enforces that with a flag: GlassSurface groups itself only when
    // it finds a BackdropGroup ancestor, and a pushed route is not a
    // descendant of the AppShell that owns the group. This test pins that
    // structural fact, because it is the thing that would silently break if
    // the group ever moved above the Navigator.
    await _pumpShell(tester);
    final shellKeys = _keys(tester);

    final context = tester.element(find.byType(AppShell));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => SizedBox(width: 200, height: 200, child: _pane()),
      ),
    );
    await tester.pumpAndSettle();

    final all = _keys(tester);
    expect(all, hasLength(shellKeys.length + 1));
    expect(
      all.where((k) => k == null),
      hasLength(1),
      reason: 'the dialog must snapshot independently',
    );
  });

  testWidgets('no group, no grouping — a bare glass surface still blurs', (
    tester,
  ) async {
    // GlassSurface is used outside the shell too (dialog bodies, popovers).
    // Losing the blur there would be a silent visual regression.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(bakedGlass: false),
        home: Scaffold(body: SizedBox(width: 300, height: 200, child: _pane())),
      ),
    );
    expect(_keys(tester), [null]);
  });
}
