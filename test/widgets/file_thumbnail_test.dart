import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';
import 'package:jellyfin_media_management_tool/services/thumbnail_service.dart';
import 'package:jellyfin_media_management_tool/widgets/file_browser/file_thumbnail.dart';

/// A 1x1 PNG. Image.memory sniffs the container, so the service's "jpeg"
/// filename doesn't have to match — this just has to be decodable bytes.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _thumbChannel = MethodChannel('fc_native_video_thumbnail');
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

FileEntry _video([String name = 'episode.mkv']) => FileEntry(
  path: '/media/$name',
  isDirectory: false,
  size: 1024,
  modified: DateTime(2026, 1, 1),
);

/// These tests cover what [FileThumbnail] *renders*; the decode pipeline itself
/// is covered in `test/services/thumbnail_service_test.dart`.
///
/// Anything that has to touch the disk cache is driven through
/// [WidgetTester.runAsync] before the widget is pumped, so the service's real
/// file I/O runs to completion in the real event loop. Letting it run *during*
/// the widget's lifecycle instead would strand every `await` continuation in
/// the fake-async zone that `testWidgets` installs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<MethodCall> calls;

  /// Installs a fake native backend. [respond] receives the invocation and
  /// returns whatever the platform would.
  void mockPlugin(Object? Function(MethodCall call) respond) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_thumbChannel, (call) async {
          calls.add(call);
          return respond(call);
        });
  }

  setUp(() {
    calls = [];
    // Each test gets its own cache directory so a JPEG written by one can't
    // satisfy the next.
    tempDir = Directory.systemTemp.createTempSync('thumb_widget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProviderChannel,
          (call) async => tempDir.path,
        );
    ThumbnailService.instance.resetForTest();
  });

  tearDown(() async {
    // The prune is fire-and-forget in production; let it finish before the
    // directory it's walking disappears.
    await ThumbnailService.instance.pendingPrune;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_thumbChannel, null)
      ..setMockMethodCallHandler(_pathProviderChannel, null);
    ThumbnailService.instance.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpThumbnail(
    WidgetTester tester, {
    required FileEntry entry,
    String label = 'Video',
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileThumbnail(
            entry: entry,
            label: label,
            iconColor: Colors.blue,
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  testWidgets('a cold row renders the type icon, not a blank gap', (
    tester,
  ) async {
    mockPlugin((_) => _pixel);

    await pumpThumbnail(tester, entry: _video());

    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a decoded frame paints on the row\'s very first build', (
    tester,
  ) async {
    mockPlugin((_) => _pixel);
    // Warm the cache the way a previous row in the same folder would have.
    await tester.runAsync(
      () => ThumbnailService.instance.thumbnailFor(_video()),
    );

    await pumpThumbnail(tester, entry: _video());

    // No pump in between: peek() must answer synchronously, otherwise
    // scrolling back over a decoded row flashes the icon for a frame.
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a file the backend cannot decode stays an icon', (tester) async {
    mockPlugin((_) => null);
    await tester.runAsync(
      () => ThumbnailService.instance.thumbnailFor(_video()),
    );

    await pumpThumbnail(tester, entry: _video());

    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('a throwing backend degrades to the icon instead of surfacing', (
    tester,
  ) async {
    mockPlugin((_) => throw PlatformException(code: 'decode-failed'));
    await tester.runAsync(
      () => ThumbnailService.instance.thumbnailFor(_video()),
    );

    await pumpThumbnail(tester, entry: _video());

    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('the disabled setting never reaches the native backend', (
    tester,
  ) async {
    mockPlugin((_) => _pixel);

    await pumpThumbnail(tester, entry: _video(), enabled: false);

    expect(calls, isEmpty);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('turning the setting off drops an already-painted poster', (
    tester,
  ) async {
    mockPlugin((_) => _pixel);
    await tester.runAsync(
      () => ThumbnailService.instance.thumbnailFor(_video()),
    );

    await pumpThumbnail(tester, entry: _video());
    expect(find.byType(Image), findsOneWidget);

    // Same State object, new props — didUpdateWidget has to re-resolve.
    await pumpThumbnail(tester, entry: _video(), enabled: false);
    // Past the AnimatedSwitcher cross-fade, which keeps the outgoing child in
    // the tree while it fades.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('non-video rows never reach the native backend', (tester) async {
    mockPlugin((_) => _pixel);

    await pumpThumbnail(
      tester,
      entry: FileEntry(
        path: '/media/poster.jpg',
        isDirectory: false,
        size: 10,
        modified: DateTime(2026, 1, 1),
      ),
      label: 'Image',
    );

    expect(calls, isEmpty);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('a recycled row does not keep the previous file\'s poster', (
    tester,
  ) async {
    // Only the first entry is decodable, so if the row still shows an Image
    // after being rebound it can only be the stale one.
    mockPlugin((call) {
      final src = (call.arguments as Map)['srcFile'] as String;
      return src.endsWith('episode.mkv') ? _pixel : null;
    });
    await tester.runAsync(
      () => ThumbnailService.instance.thumbnailFor(_video()),
    );

    await pumpThumbnail(tester, entry: _video());
    expect(find.byType(Image), findsOneWidget);

    await pumpThumbnail(tester, entry: _video('other.mkv'));
    // Past the AnimatedSwitcher cross-fade, which keeps the outgoing child in
    // the tree while it fades.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });
}
