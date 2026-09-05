import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/glass/glass_panel.dart';

Future<void> _pump(WidgetTester tester, GlassPanel panel) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, height: 200, child: panel)),
    ),
  ),
);

/// The light theme's real centre-table gradient, all three stops opaque.
const _opaqueTableGradient = LinearGradient(
  colors: [Color(0xFFEFF3FE), Color(0xFFFFFFFF), Color(0xFFEFF7F3)],
  stops: [0.0, 0.5, 1.0],
);

void main() {
  final blur = find.byType(BackdropFilter);

  testWidgets('an opaque gradient drops the blur it would paint over', (
    tester,
  ) async {
    // The regression: this is the light theme's table card. Its fill covers
    // every pixel the BackdropFilter produced, so the blur was a full-panel,
    // multi-pass GPU filter re-run each frame for an invisible result.
    await _pump(
      tester,
      const GlassPanel(gradient: _opaqueTableGradient, child: SizedBox()),
    );
    expect(blur, findsNothing);
  });

  testWidgets('a translucent gradient keeps it — the blur shows through', (
    tester,
  ) async {
    await _pump(
      tester,
      GlassPanel(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3B6FF5).withValues(alpha: 0.22),
            const Color(0xFF22C9A9).withValues(alpha: 0.18),
          ],
        ),
        child: const SizedBox(),
      ),
    );
    expect(blur, findsOneWidget);
  });

  testWidgets('the same rule applies to a solid fill', (tester) async {
    await _pump(
      tester,
      const GlassPanel(fill: Color(0xFFFFFFFF), child: SizedBox()),
    );
    expect(blur, findsNothing);

    await _pump(
      tester,
      GlassPanel(
        fill: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
        child: const SizedBox(),
      ),
    );
    expect(blur, findsOneWidget);
  });

  testWidgets('blur: false still wins over a translucent fill', (tester) async {
    await _pump(
      tester,
      GlassPanel(
        blur: false,
        fill: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
        child: const SizedBox(),
      ),
    );
    expect(blur, findsNothing);
  });

  testWidgets('the default translucent panel fill is still frosted', (
    tester,
  ) async {
    // Nothing above should have made the glass panes opaque by accident.
    await _pump(tester, const GlassPanel(child: SizedBox()));
    expect(blur, findsOneWidget);
    final filter = tester.widget<BackdropFilter>(blur).filter;
    expect(filter, isA<ImageFilter>());
  });

  group('performance mode', () {
    Future<void> pumpReduced(WidgetTester tester, GlassPanel panel) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(reduceEffects: true),
            home: Scaffold(
              body: Center(
                child: SizedBox(width: 300, height: 200, child: panel),
              ),
            ),
          ),
        );

    testWidgets('skips the filter instead of passing a zero sigma', (
      tester,
    ) async {
      // A zero-sigma BackdropFilter is not free: it still ends the render pass
      // and reads back the whole target, which is where the cost is. The
      // widget has to go, not just its sigma.
      await pumpReduced(tester, const GlassPanel(child: SizedBox()));
      expect(blur, findsNothing);
    });

    testWidgets('drops the elevated drop shadow too', (tester) async {
      await _pump(tester, const GlassPanel(elevated: true, child: SizedBox()));
      expect(_shadowed(tester), isTrue);

      await pumpReduced(
        tester,
        const GlassPanel(elevated: true, child: SizedBox()),
      );
      // MaterialApp animates a theme swap over kThemeAnimationDuration, and
      // GlassTheme.lerp only flips the flag at the halfway mark — so the
      // panel is still the frosted one on the frame right after the pump.
      await tester.pumpAndSettle();
      expect(_shadowed(tester), isFalse);
    });
  });
}

/// Whether anything in the tree paints a drop shadow.
bool _shadowed(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .any(
      (d) =>
          d.decoration is BoxDecoration &&
          ((d.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false),
    );
