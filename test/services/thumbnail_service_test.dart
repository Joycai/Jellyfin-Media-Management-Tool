import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';
import 'package:jellyfin_media_management_tool/services/thumbnail_service.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _thumbChannel = MethodChannel('fc_native_video_thumbnail');
const _nativeChannel = MethodChannel('jellyfin/thumbnail');
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

FileEntry _video([String name = 'episode.mkv']) => FileEntry(
  path: '/media/$name',
  isDirectory: false,
  size: 1024,
  modified: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<MethodCall> calls;

  void mockPlugin(Object? Function(MethodCall call) respond) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_thumbChannel, (call) async {
          calls.add(call);
          return respond(call);
        });
  }

  setUp(() {
    calls = [];
    tempDir = Directory.systemTemp.createTempSync('thumb_svc_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProviderChannel,
          (call) async => tempDir.path,
        );
    ThumbnailService.instance.resetForTest();
    // These tests are about the plugin path, which is what macOS and Linux
    // use. Pinned explicitly rather than left to the host: on Windows the
    // service prefers the runner channel, and the fallback would make every
    // assertion below depend on which machine ran it.
    ThumbnailService.instance.useNativeChannelForTest(false);
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

  test('decodes a frame and asks the backend only once per entry', () async {
    mockPlugin((_) => _pixel);

    final first = await ThumbnailService.instance.thumbnailFor(_video());
    expect(first, isNotNull);
    final callsAfterFirst = calls.length;

    // Second request for the same entry is served from the in-memory LRU.
    final second = await ThumbnailService.instance.thumbnailFor(_video());
    expect(second, isNotNull);
    expect(calls, hasLength(callsAfterFirst));
    expect(ThumbnailService.instance.peek(_video()), isNotNull);
  });

  test(
    'seeks first, then retries the first frame when seeking yields null',
    () async {
      mockPlugin((call) {
        final args = call.arguments as Map;
        return args.containsKey('atUs') ? null : _pixel;
      });

      expect(await ThumbnailService.instance.thumbnailFor(_video()), isNotNull);
      expect(calls, hasLength(2));
      expect((calls.first.arguments as Map)['atUs'], isNotNull);
      expect((calls.last.arguments as Map).containsKey('atUs'), isFalse);
    },
  );

  test('a null result is cached as a failure and never retried', () async {
    mockPlugin((_) => null);

    expect(await ThumbnailService.instance.thumbnailFor(_video()), isNull);
    final after = calls.length;
    expect(await ThumbnailService.instance.thumbnailFor(_video()), isNull);
    expect(calls, hasLength(after), reason: 'failures are not retried');
  });

  test('a throwing backend degrades to null rather than propagating', () async {
    mockPlugin((_) => throw PlatformException(code: 'decode-failed'));

    expect(await ThumbnailService.instance.thumbnailFor(_video()), isNull);
  });

  test('the disk cache survives a cleared memory cache', () async {
    mockPlugin((_) => _pixel);

    expect(await ThumbnailService.instance.thumbnailFor(_video()), isNotNull);
    expect(await ThumbnailService.instance.cacheSizeOnDisk(), greaterThan(0));

    // Simulate a fresh session: same disk cache, empty memory cache. The
    // backend must not be consulted again.
    final before = calls.length;
    ThumbnailService.instance.resetForTest();
    expect(await ThumbnailService.instance.thumbnailFor(_video()), isNotNull);
    expect(calls, hasLength(before));
  });

  test('a re-encoded file under the same name gets a new key', () async {
    mockPlugin((_) => _pixel);

    await ThumbnailService.instance.thumbnailFor(_video());
    final before = calls.length;

    // Same path, different mtime/size — must miss both cache tiers.
    final edited = FileEntry(
      path: '/media/episode.mkv',
      isDirectory: false,
      size: 2048,
      modified: DateTime(2026, 6, 1),
    );
    expect(await ThumbnailService.instance.thumbnailFor(edited), isNotNull);
    expect(calls.length, greaterThan(before));
  });

  test('clearCache empties both tiers', () async {
    mockPlugin((_) => _pixel);

    await ThumbnailService.instance.thumbnailFor(_video());
    expect(ThumbnailService.instance.peek(_video()), isNotNull);

    await ThumbnailService.instance.clearCache();
    expect(ThumbnailService.instance.peek(_video()), isNull);
    expect(await ThumbnailService.instance.cacheSizeOnDisk(), 0);
  });

  group('the Windows runner channel', () {
    // fc_native_video_thumbnail runs its Shell extraction inline on the
    // platform thread on Windows, so one NAS video stalls the window's message
    // loop while it is read over SMB. The runner answers this channel from a
    // worker pool instead; see windows/runner/thumbnail_channel.h.
    late List<MethodCall> nativeCalls;

    void mockNative(Object? Function(MethodCall call) respond) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_nativeChannel, (call) async {
            nativeCalls.add(call);
            return respond(call);
          });
    }

    setUp(() {
      nativeCalls = [];
      ThumbnailService.instance.useNativeChannelForTest(true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_nativeChannel, null);
    });

    test('is preferred over the plugin, and asks it nothing', () async {
      mockNative((_) => _pixel);
      mockPlugin((_) => _pixel);

      expect(await ThumbnailService.instance.thumbnailFor(_video()), isNotNull);
      expect(nativeCalls, hasLength(1));
      expect(nativeCalls.single.method, 'extract');
      expect(
        (nativeCalls.single.arguments as Map)['path'],
        '/media/episode.mkv',
      );
      expect(
        calls,
        isEmpty,
        reason: 'the plugin must not be consulted on this path',
      );
    });

    test('makes one call, not the plugin two-step', () async {
      // The Shell takes no timestamp, so there is no seeked attempt to retry
      // without. Asking twice would just double the SMB round trips.
      mockNative((_) => _pixel);
      await ThumbnailService.instance.thumbnailFor(_video());
      expect(nativeCalls, hasLength(1));
      expect(
        (nativeCalls.single.arguments as Map).containsKey('atUs'),
        isFalse,
      );
    });

    test('no frame is cached as a failure, same as the plugin', () async {
      mockNative((_) => null);
      expect(await ThumbnailService.instance.thumbnailFor(_video()), isNull);
      final after = nativeCalls.length;
      expect(await ThumbnailService.instance.thumbnailFor(_video()), isNull);
      expect(nativeCalls, hasLength(after));
    });

    test(
      'an older runner without the channel falls back to the plugin',
      () async {
        // A Dart-only hot restart can land on a binary built before the channel
        // existed. Thumbnails must keep working there — just on the old, slow
        // path — rather than disappearing.
        mockPlugin((_) => _pixel);
        // No handler registered for the native channel, so it raises
        // MissingPluginException exactly as that runner would.

        expect(
          await ThumbnailService.instance.thumbnailFor(_video()),
          isNotNull,
        );
        expect(calls, isNotEmpty);

        // And the fallback latches: no second probe per file.
        final before = calls.length;
        expect(
          await ThumbnailService.instance.thumbnailFor(_video('other.mkv')),
          isNotNull,
        );
        expect(calls.length, greaterThan(before));
        expect(nativeCalls, isEmpty);
      },
    );
  });

  test('canThumbnail only accepts video files', () {
    expect(ThumbnailService.canThumbnail(_video(), 'Video'), isTrue);
    expect(ThumbnailService.canThumbnail(_video(), 'Image'), isFalse);
    expect(
      ThumbnailService.canThumbnail(
        FileEntry(
          path: '/media/Season 01',
          isDirectory: true,
          size: 0,
          modified: DateTime(2026, 1, 1),
        ),
        'Video',
      ),
      isFalse,
    );
  });
}
