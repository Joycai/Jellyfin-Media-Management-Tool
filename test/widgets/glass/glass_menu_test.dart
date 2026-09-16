import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/glass/glass_menu.dart';

/// showGlassMenu and its entry builders are the skin every context menu in the
/// app wears -- the file table's, the artwork tiles' role menu. Nothing
/// rendered one in a test before.
Future<void> _pump(
  WidgetTester tester,
  void Function(Future<String?>) capture,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => capture(
              showGlassMenu<String>(
                context,
                globalPosition: const Offset(200, 200),
                items: [
                  glassMenuHeader<String>(context, 'MARK AS'),
                  glassMenuItem<String>(
                    context,
                    value: 'poster',
                    icon: Icons.image_outlined,
                    label: 'Poster',
                    selected: true,
                  ),
                  glassMenuItem<String>(
                    context,
                    value: 'delete',
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    trailing: 'Del',
                    color: Colors.red,
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rows render with their label, icon and trailing hint', (
    tester,
  ) async {
    await _pump(tester, (_) {});

    expect(find.text('MARK AS'), findsOneWidget);
    expect(find.text('Poster'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Del'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('tapping a row returns its value', (tester) async {
    String? result;
    await _pump(tester, (f) => f.then((v) => result = v));

    await tester.tap(find.text('Poster'));
    await tester.pumpAndSettle();

    expect(result, 'poster');
  });

  testWidgets('a coloured destructive row still returns its value', (
    tester,
  ) async {
    String? result;
    await _pump(tester, (f) => f.then((v) => result = v));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, 'delete');
  });

  testWidgets('the header is a caption, not a choice', (tester) async {
    var returned = false;
    await _pump(tester, (f) => f.then((_) => returned = true));

    await tester.tap(find.text('MARK AS'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // A disabled PopupMenuItem does not pop the route, so the menu is still
    // up and the future has not completed.
    expect(returned, isFalse);
    expect(find.text('Poster'), findsOneWidget);
  });
}
