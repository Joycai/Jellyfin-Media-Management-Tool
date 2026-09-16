import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/shell/secondary_title_bar.dart';

/// The 48px bar every full-page route wears. Its content row only gets its
/// height from a child, and on macOS there is no `WindowCaptionButtons` to
/// supply it -- so the row collapsed to the tallest control and sat against the
/// top of the Stack, floating the back button, the title and the breadcrumb
/// 10px above the system traffic lights.
void main() {
  testWidgets('on macOS the bar centers its content on the 48px mid-line', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              SecondaryTitleBar(
                backLabel: 'Back',
                onBack: () {},
                title: 'Settings',
                subtitle: 'Appearance',
                actions: const [Text('v 0.0.0')],
              ),
            ],
          ),
        ),
      ),
    );

    final bar = tester.getRect(find.byType(SecondaryTitleBar));
    expect(bar.height, AppSizes.topBar);
    for (final label in ['Back', 'Settings', 'Appearance', 'v 0.0.0']) {
      expect(
        tester.getRect(find.text(label)).center.dy,
        moreOrLessEquals(bar.center.dy, epsilon: 0.5),
        reason: '"$label" is off the bar\'s vertical center',
      );
    }

    // The framework asserts this is unset before the body returns.
    debugDefaultTargetPlatformOverride = null;
  });
}
