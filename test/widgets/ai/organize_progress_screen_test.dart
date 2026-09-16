import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/organize/apply_controller.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/ai/organize_progress_screen.dart';
import 'package:provider/provider.dart';

/// An empty plan logs two lines and touches no disk, which is all a teardown
/// test needs from it.
ApplyController _controller() => ApplyController(
  plan: OrganizePlan(
    mediaType: 'movie',
    targetRoot: 'Movies',
    reasoning: const [],
    actions: const [],
  ),
  baseDir: '/work',
  backup: false,
  totalBytes: 0,
);

void main() {
  testWidgets('tearing the screen down does not reach for an ancestor', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ApplyController>.value(
        value: _controller(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          theme: AppTheme.light(),
          home: const OrganizeProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('activity.log'), findsOneWidget);

    // Unmounting runs dispose(). It used to call context.read<ApplyController>
    // from there, and an ancestor lookup on a deactivated element throws --
    // which leaked the auto-scroll listener as well as failing the frame.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
