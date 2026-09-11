import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_cancel_token.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/task_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/tasks/tasks_screen.dart';
import 'package:provider/provider.dart';

/// An analysis that never finishes, so its task stays running for the test.
class _HangingAi extends AiService {
  final _never = Completer<OrganizePlan>();

  @override
  Future<OrganizePlan> analyzeFolder(
    String baseDir, {
    String? titleHint,
    String? mediaTypeHint,
    Set<String>? onlyPaths,
    AiCancelToken? cancelToken,
    void Function(double fraction)? onProgress,
  }) => _never.future;
}

Future<void> _pumpTasks(WidgetTester tester, TaskService tasks) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<TaskService>.value(
      value: tasks,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        home: const Scaffold(body: TasksScreen()),
      ),
    ),
  );
  // Not pumpAndSettle: an indeterminate bar animates forever.
  await tester.pump();
}

void main() {
  testWidgets('a running analyze task renders its card, not an error', (
    tester,
  ) async {
    final tasks = TaskService();
    tasks.startAnalyze(ai: _HangingAi(), baseDir: '/media/Some Show');

    await _pumpTasks(tester, tasks);

    // A running analyze task has no fraction to show. Feeding that null to
    // the progress tween threw on the first frame, which a release build
    // paints as a grey box covering the whole list.
    expect(tester.takeException(), isNull);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull, reason: 'no fraction yet: indeterminate');
  });
}
