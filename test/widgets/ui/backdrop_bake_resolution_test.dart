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
  /// Pumps the shell at [logical] logical pixels on a [dpr] display and returns
  /// the sharp baked image.
  Future<ui.Image> bake(
    WidgetTester tester,
    Size logical,
    double dpr, {
    bool bakedGlass = true,
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(bakedGlass: bakedGlass),
        home: const AppShell(
          titleBar: SizedBox(height: 48),
          body: SizedBox.expand(),
        ),
      ),
    );
    // Waits out the 120ms debounce and the async `toImage`.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final raw = tester.widget<RawImage>(
      find
          .descendant(
            of: find.byType(AppBackdrop),
            matching: find.byType(RawImage),
          )
          .first,
    );
    return raw.image!;
  }

  testWidgets('the sharp bake is sized in device pixels, not logical ones', (
    tester,
  ) async {
    // 800 logical px wide snaps up to 832 (the 64-logical-px quantum), then
    // 2 device px per texel: the width tracks devicePixelRatio exactly.
    for (final (dpr, width) in [(1.0, 416), (2.0, 832), (3.0, 1248)]) {
      expect(
        (await bake(tester, const Size(800, 600), dpr)).width,
        width,
        reason: 'dpr $dpr should bake 832 logical px at 2 device px per texel',
      );
    }
  });

  testWidgets('the re-bake quantum is counted in logical pixels', (
    tester,
  ) async {
    // Both snap to the same 832x640 logical box, so the second pump must reuse
    // the first image rather than rasterize a new one. Counting the quantum in
    // texels instead would make this threshold shift with dpr and with the
    // downscale, and the sharp layer would re-bake four times as often as the
    // blurred copies it has to stay in step with.
    final first = await bake(tester, const Size(800, 600), 2);
    final second = await bake(tester, const Size(830, 600), 2);
    expect(identical(first, second), isTrue);

    // One quantum further really is a new bake.
    final third = await bake(tester, const Size(900, 600), 2);
    expect(identical(first, third), isFalse);
    expect(third.width, 960);
  });

  testWidgets('the texture ceiling scales both axes together', (tester) async {
    // Wider than 8192 device px — a window spanned across two 5K displays.
    // Clamping the long axis alone would leave the image a different shape from
    // the window, and `RadialGradient.radius` is a fraction of the short side,
    // so `BoxFit.fill` would draw the circles as ellipses.
    final image = await bake(
      tester,
      const Size(5120, 1440),
      2,
      // Blurring a texture this size in the software rasterizer is pure test
      // latency; the ceiling is a property of the sharp layer.
      bakedGlass: false,
    );
    expect(image.width, 4096);
    expect(
      image.width / image.height,
      closeTo(5120 / 1472, 0.01), // 1440 snaps up one quantum to 1472
      reason: 'the clamp must preserve the baked aspect',
    );
  });
}
