import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/shell/app_shell.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/glass_surface.dart';

/// The four shell panels sit on nothing but `AppBackdrop`'s baked image, so
/// their blur is static too and can be baked with it. That turns four
/// full-size render-target readbacks into four textured quads — measured
/// ~46ms/frame maximized at 4K, which was 57% of the whole frame.
///
/// It only holds while nothing dynamic is *behind* a panel, and that is a
/// structural fact about the widget tree rather than something a flag
/// enforces. These tests are what pins it.

Widget _pane({Widget? child}) =>
    AppGlassPane(child: child ?? const SizedBox.expand());

Future<void> _pumpShell(
  WidgetTester tester, {
  bool bakedGlass = true,
  Widget? body,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark(bakedGlass: bakedGlass),
    home: AppShell(
      titleBar: SizedBox(height: 48, child: _pane()),
      body: body ?? _pane(),
      statusBar: SizedBox(height: 28, child: _pane()),
    ),
  ),
);

/// Waits out `AppBackdrop`'s 120ms debounce and the async `toImage`.
Future<void> _settleBake(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

int _filters(WidgetTester tester) => tester
    .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
    .length;

void main() {
  testWidgets('the shell panels stop filtering once the bake lands', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Before the first bake there is no image to crop, so the panels blur the
    // ordinary way. That interim matters: dropping the blur for the first few
    // frames would read as a flash on every window open.
    expect(_filters(tester), 3, reason: 'live filters until the bake lands');

    await _settleBake(tester);

    expect(
      _filters(tester),
      0,
      reason:
          'every shell panel should now be drawing a crop of the '
          'pre-blurred backdrop instead of running a filter',
    );
  });

  testWidgets('turning baking off keeps the live filters', (tester) async {
    await _pumpShell(tester, bakedGlass: false);
    await _settleBake(tester);
    expect(_filters(tester), 3);
  });

  testWidgets('a glass surface nested in another still filters for real', (
    tester,
  ) async {
    // This is the constraint, and the reason GlassSurface shadows the scope
    // for its own subtree. What is behind an inner panel is not the backdrop —
    // it is the outer panel's fill and content. Handing it the baked image
    // would quietly erase both from its blur.
    await _pumpShell(tester, body: _pane(child: _pane()));
    await _settleBake(tester);

    expect(
      _filters(tester),
      1,
      reason: 'the outer panels bake; the nested one must not',
    );
  });

  testWidgets('a dialog above the shell is never baked', (tester) async {
    // Dialogs are pushed routes, so they are not descendants of the shell's
    // AppBackdrop and cannot reach its images — the same structural split that
    // keeps them out of the BackdropGroup. They must blur the panels
    // themselves, which no pre-baked background contains.
    await _pumpShell(tester);
    await _settleBake(tester);
    expect(_filters(tester), 0);

    final context = tester.element(find.byType(AppShell));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => SizedBox(width: 200, height: 200, child: _pane()),
      ),
    );
    await tester.pumpAndSettle();

    expect(_filters(tester), 1, reason: 'the dialog blurs live');
  });

  testWidgets('glass intensity 0 leaves nothing to bake', (tester) async {
    // reduceEffects and baking are different axes, but 0 has no blur to
    // compute, so AppTokens forces baking off rather than leaving a state
    // where `bakedGlass` is true and no bake exists.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(glassIntensity: 0),
        home: AppShell(
          titleBar: SizedBox(height: 48, child: _pane()),
          body: _pane(),
          statusBar: SizedBox(height: 28, child: _pane()),
        ),
      ),
    );
    await _settleBake(tester);
    expect(_filters(tester), 0);
  });
}
