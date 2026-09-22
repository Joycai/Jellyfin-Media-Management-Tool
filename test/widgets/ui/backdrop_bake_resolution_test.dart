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
/// device pixels, and that is what this pins.
void main() {
  Future<int> bakedWidth(WidgetTester tester, double dpr) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(800 * dpr, 600 * dpr);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
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
    return raw.image!.width;
  }

  testWidgets('the sharp bake is sized in device pixels, not logical ones', (
    tester,
  ) async {
    // 800 logical px wide, 2 device px per texel, quantised to 16.
    expect(await bakedWidth(tester, 1), 400);
    expect(await bakedWidth(tester, 2), 800);
    expect(await bakedWidth(tester, 3), 1200);
  });
}
