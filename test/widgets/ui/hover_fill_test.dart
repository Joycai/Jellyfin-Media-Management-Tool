import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_controls.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_controls.dart';

/// What a hover fades *through*, and whether it lands anywhere visible.
///
/// Both halves of this were wrong on the About page's links, and neither is
/// something a screenshot of the settled state can show: the fill flashed dark
/// grey on the way in and then settled on a colour ~4/255 from the card it sat
/// on, so the whole hover read as "it lit up and went away".
Color _fillOf(WidgetTester tester, Finder button) {
  final box = tester.widget<AnimatedContainer>(
    find.descendant(of: button, matching: find.byType(AnimatedContainer)),
  );
  return (box.decoration! as BoxDecoration).color!;
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: SettingsCard(
              child: AppButton.ghost(label: 'Issues', onPressed: () {}),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(target));
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
  testWidgets('a ghost button rests on its hover colour at alpha zero', (
    tester,
  ) async {
    await _pump(tester, brightness: Brightness.light);
    final button = find.byType(AppButton);

    final resting = _fillOf(tester, button);
    await _hover(tester, button);
    final hovered = _fillOf(tester, button);

    // `Colors.transparent` is transparent *black*, and `Color.lerp` does not
    // premultiply — it walks r, g and b independently, so a fade from it to
    // any light colour passes through 50% mid-grey. On a white card that is a
    // visible dark flash on the way in and on the way out.
    expect(resting.a, 0);
    expect(hovered.a, greaterThan(0));
    expect(
      (resting.r, resting.g, resting.b),
      (hovered.r, hovered.g, hovered.b),
      reason: 'the resting fill must be the hover colour at alpha 0',
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('a ghost button hover is visible on a $brightness card', (
      tester,
    ) async {
      await _pump(tester, brightness: brightness);
      final button = find.byType(AppButton);
      final t = Theme.of(
        tester.element(find.byType(SettingsCard)),
      ).extension<AppTokens>()!;
      // Both the card and the hover are translucent washes, so they have to be
      // laid on the opaque window ground before they can be compared at all.
      final ground = Color.alphaBlend(t.cardFill, t.windowBase);

      await _hover(tester, button);
      final over = Color.alphaBlend(_fillOf(tester, button), ground);

      // Channel distance rather than luminance: a dark theme lives in the
      // bottom hundredth of the luminance range, where every threshold that
      // means something in the light theme is met by nothing at all.
      final shift = [
        (over.r - ground.r).abs(),
        (over.g - ground.g).abs(),
        (over.b - ground.b).abs(),
      ].reduce((a, b) => a > b ? a : b);

      // A ghost button brings no ground of its own, so its hover lands on
      // whatever is behind it. `controlFill` is a white wash in the light
      // theme; over a card that is already white 85% it shifted the ground by
      // 4/255 — the hover was drawn, and invisible.
      expect(
        shift,
        greaterThan(8 / 255),
        reason: 'hover on a $brightness card must be visible',
      );
    });
  }
}
