import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/shell/app_shell.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_backdrop.dart';

/// `AppBackdrop` bakes the window gradients into an image and stretches it back
/// over the window. The stretch factor is the whole game: the gradient is
/// rasterized *with dither* — a +/-1 per-pixel noise Skia and Impeller add so
/// that 8-bit quantisation leaves no contour on a layer this faint — and the
/// stretch magnifies that noise along with everything else.
///
/// Sizing the bake off **logical** pixels made the factor scale with the
/// display: 4 on a 1x screen and 8 on a Retina one, where 1px of dither became
/// an 8px blob and the backdrop read as a dishcloth. So the downscale is in
/// device pixels — and the two things that arithmetic then has to keep straight
/// are the re-bake quantum and the texture ceiling, one test each below.
void main() {
  late ThemeData theme;

  /// Pumps the shell at [logical] logical pixels on a [dpr] display and settles
  /// the bake.
  Future<void> pumpShell(
    WidgetTester tester,
    Size logical,
    double dpr, {
    bool bakedGlass = true,
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    addTearDown(tester.view.reset);

    theme = AppTheme.dark(bakedGlass: bakedGlass);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const AppShell(
          titleBar: SizedBox(height: 48),
          body: SizedBox.expand(),
        ),
      ),
    );
    // Waits out the 120ms debounce and the async `toImage`.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  /// The sharp image, as `RawImage` receives it.
  ui.Image sharp(WidgetTester tester) => tester
      .widget<RawImage>(
        find
            .descendant(
              of: find.byType(AppBackdrop),
              matching: find.byType(RawImage),
            )
            .first,
      )
      .image!;

  /// One of the pre-blurred copies `GlassSurface` crops out of, reached the way
  /// a panel reaches it.
  ui.Image blurred(WidgetTester tester) {
    final scope = tester.widget<BakedBackdropScope>(
      find
          .descendant(
            of: find.byType(AppBackdrop),
            matching: find.byType(BakedBackdropScope),
          )
          .first,
    );
    return scope.backdrop!.imageFor(theme.extension<AppTokens>()!.blurPanel)!;
  }

  testWidgets('the sharp bake is sized in device pixels, not logical ones', (
    tester,
  ) async {
    // 800 logical px wide snaps up to 832 (the 64-logical-px quantum), then
    // 2 device px per texel: the width tracks devicePixelRatio exactly.
    for (final (dpr, width) in [(1.0, 416), (2.0, 832), (3.0, 1248)]) {
      await pumpShell(tester, const Size(800, 600), dpr);
      expect(
        sharp(tester).width,
        width,
        reason: 'dpr $dpr should bake 832 logical px at 2 device px per texel',
      );
    }
  });

  testWidgets('the re-bake quantum is counted in logical pixels', (
    tester,
  ) async {
    // Quantising in *texel* space instead would make the same number mean a
    // different amount of window movement per layer and per display scale. Two
    // consequences, one per half of this test.
    //
    // Note dpr 1 rather than 2: at dpr 2 the sharp layer's device-per-texel is
    // exactly 1, so both quantisation orders agree on its size and the sharp
    // image alone proves nothing.
    await pumpShell(tester, const Size(800, 600), 1);
    final first = sharp(tester);
    await pumpShell(tester, const Size(830, 600), 1);
    expect(
      identical(first, sharp(tester)),
      isTrue,
      reason: '800 and 830 both snap to 832 logical px — no re-bake',
    );

    await pumpShell(tester, const Size(900, 600), 1);
    expect(sharp(tester).width, 480, reason: '960 logical px / 2 device px');

    // And the layers stay locked to each other: they snap once, together, so
    // the blurred copy is exactly half the sharp one on both axes at every
    // size. Quantise per layer in texel space and they drift — 1026 logical px
    // at dpr 2 lands on 1040/528, a ratio of 1.97, and the two start re-baking
    // at different moments.
    for (final (logical, dpr) in [
      (const Size(1026, 700), 2.0),
      (const Size(900, 650), 1.0),
      (const Size(1400, 900), 3.0),
    ]) {
      await pumpShell(tester, logical, dpr);
      final s = sharp(tester);
      final b = blurred(tester);
      expect(b.width * 2, s.width, reason: 'width at $logical dpr $dpr');
      expect(b.height * 2, s.height, reason: 'height at $logical dpr $dpr');
    }
  });

  testWidgets('the texture ceiling scales both axes together', (tester) async {
    // Wider than 8192 device px — a window spanned across two 5K displays.
    // Clamping the long axis alone would leave the image a different shape from
    // the window, and `RadialGradient.radius` is a fraction of the short side,
    // so `BoxFit.fill` would draw the circles as ellipses.
    await pumpShell(
      tester,
      const Size(5120, 1440),
      2,
      // Blurring a texture this size in the software rasterizer is pure test
      // latency; the ceiling is a property of the sharp layer.
      bakedGlass: false,
    );
    final image = sharp(tester);
    expect(image.width, 4096);
    expect(
      image.width / image.height,
      closeTo(5120 / 1472, 0.01), // 1440 snaps up one quantum to 1472
      reason: 'the clamp must preserve the baked aspect',
    );
  });
}
