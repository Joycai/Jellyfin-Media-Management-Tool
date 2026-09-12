import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/shell/app_shell.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_controls.dart';

/// The font the user picks in Settings has to reach every surface, and the
/// mono styles have to name a family that exists somewhere.
///
/// Neither is visible in a screenshot unless you know what the right answer
/// looks like: a surface that lost the family renders in the platform default,
/// which on a machine with no font choice is indistinguishable from correct.
const _picked = 'HarmonyOS Sans SC';

TextStyle _styleOf(WidgetTester tester, Finder text) {
  final rich = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  return (rich.text as TextSpan).style!;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(fontFamily: _picked),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('ordinary text carries the picked family and the CJK fallback', (
    tester,
  ) async {
    await _pump(tester, const Text('plain'));

    final style = _styleOf(tester, find.text('plain'));
    expect(style.fontFamily, _picked);
    expect(style.fontFamilyFallback, isNotEmpty);
  });

  testWidgets('a mono style names a family that exists on this platform', (
    tester,
  ) async {
    await _pump(tester, const Text('42', style: AppTypeScale.monoSmall));

    final style = _styleOf(tester, find.text('42'));
    expect(style.fontFamily, AppTypeScale.mono);
    // The design's JetBrains Mono is neither bundled nor installed anywhere by
    // default, and "monospace" is a CSS/Android generic that Windows and macOS
    // do not have. Without a real chain behind it the engine walked on to the
    // theme's CJK fallback and drew every path and token count in Microsoft
    // YaHei — proportional, and not the font the user picked either.
    expect(style.fontFamilyFallback, AppTypeScale.monoFallback);
    expect(style.fontFamilyFallback, contains('Consolas'));
    expect(style.fontFamilyFallback, contains('Menlo'));
    // Paths have Chinese directory names in them, and this list replaces the
    // theme's, so the CJK families have to be on it too.
    expect(style.fontFamilyFallback, contains('Microsoft YaHei UI'));
  });

  testWidgets('a column header keeps the picked family', (tester) async {
    // `DefaultTextStyle` replaces the ambient style; only `.merge` keeps the
    // family and the fallback. Three surfaces used the plain constructor —
    // the status bar, the table footer and this header — so they stayed on
    // the platform font whatever the user chose.
    await _pump(tester, const AppColumnHeader(children: [Text('Name')]));

    expect(_styleOf(tester, find.text('Name')).fontFamily, _picked);
  });

  testWidgets('the status bar keeps the picked family', (tester) async {
    await _pump(tester, const AppStatusBar(leading: [Text('12 items')]));

    expect(_styleOf(tester, find.text('12 items')).fontFamily, _picked);
  });
}
