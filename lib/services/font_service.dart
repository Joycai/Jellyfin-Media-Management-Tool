import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The UI font the user picked in Settings → Appearance.
enum AppFontChoice { system, harmony, misans }

extension AppFontChoiceX on AppFontChoice {
  /// Stable id persisted in config.json.
  String get id => switch (this) {
    AppFontChoice.system => 'system',
    AppFontChoice.harmony => 'harmony',
    AppFontChoice.misans => 'misans',
  };

  static AppFontChoice fromId(String? id) => switch (id) {
    'harmony' => AppFontChoice.harmony,
    'misans' => AppFontChoice.misans,
    _ => AppFontChoice.system,
  };
}

class _FontSpec {
  /// Family name registered with [FontLoader] and passed to `ThemeData`.
  final String family;

  /// Download URLs, tried in order (first is the primary source).
  final List<String> urls;

  /// Which zip entries to extract — Regular/Medium/Bold weights; the engine
  /// picks the right file per TextStyle from each font's internal weight.
  final String entryPattern;

  const _FontSpec({
    required this.family,
    required this.urls,
    required this.entryPattern,
  });
}

/// Downloads, extracts, registers and remembers optional UI fonts
/// (HarmonyOS Sans / MiSans). Font packages are official zips fetched once
/// into `<app-support>/fonts/<id>/`; subsequent launches just load the TTFs.
class FontService extends ChangeNotifier {
  static const Map<AppFontChoice, _FontSpec> _specs = {
    AppFontChoice.harmony: _FontSpec(
      family: 'HarmonyOS Sans SC',
      urls: [
        // Official zip mirrored on GitHub (huawei-fonts org).
        'https://github.com/huawei-fonts/HarmonyOS-Sans/raw/main/HarmonyOS%20Sans.zip',
        // GitHub-proxy fallback for networks where raw downloads stall.
        'https://ghfast.top/https://github.com/huawei-fonts/HarmonyOS-Sans/raw/main/HarmonyOS%20Sans.zip',
      ],
      // e.g. HarmonyOS Sans/HarmonyOS_Sans_SC/HarmonyOS_Sans_SC_Regular.ttf
      entryPattern: r'HarmonyOS[ _]?Sans[ _]?SC[ _-](Regular|Medium|Bold)\.ttf$',
    ),
    AppFontChoice.misans: _FontSpec(
      family: 'MiSans',
      urls: [
        // Official Xiaomi CDN (stable for years, CN-friendly).
        'https://cdn.cnbj1.fds.api.mi-img.com/vipmlmodel/font/MiSans/MiSans.zip',
        'https://hyperos.mi.com/font-download/MiSans.zip',
      ],
      // e.g. MiSans/ttf/MiSans-Regular.ttf
      entryPattern: r'MiSans-(Regular|Medium|Bold)\.ttf$',
    ),
  };

  /// 0.0–1.0 while a download runs, null otherwise.
  double? _progress;

  /// Bytes received / total for the progress dialog (0 total = unknown).
  int _receivedBytes = 0;
  int _totalBytes = 0;

  AppFontChoice? _downloading;
  final Set<AppFontChoice> _loaded = {};

  /// Fonts whose TTFs exist on disk (registered with the engine or not).
  final Set<AppFontChoice> _downloadedOnDisk = {};

  double? get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  AppFontChoice? get downloading => _downloading;

  /// Family name for [choice], or null if it's the system font or the font
  /// isn't registered with the engine yet (not downloaded / not loaded).
  String? familyFor(AppFontChoice choice) {
    if (choice == AppFontChoice.system) return null;
    return _loaded.contains(choice) ? _specs[choice]!.family : null;
  }

  bool isLoaded(AppFontChoice choice) => _loaded.contains(choice);

  /// Synchronous downloaded-state for the settings UI (filled by [init]).
  bool isDownloadedSync(AppFontChoice choice) =>
      choice == AppFontChoice.system || _downloadedOnDisk.contains(choice);

  /// Scans the font directory once at startup so the settings UI can show
  /// accurate "downloaded / needs download" badges without async lookups.
  Future<void> init() async {
    for (final choice in const [AppFontChoice.harmony, AppFontChoice.misans]) {
      if (await isDownloaded(choice)) _downloadedOnDisk.add(choice);
    }
  }

  Future<Directory> _fontDir(AppFontChoice choice) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'fonts', choice.id));
  }

  Future<List<File>> _localFontFiles(AppFontChoice choice) async {
    final dir = await _fontDir(choice);
    if (!await dir.exists()) return const [];
    return dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.ttf'))
        .cast<File>()
        .toList();
  }

  Future<bool> isDownloaded(AppFontChoice choice) async {
    if (choice == AppFontChoice.system) return true;
    return (await _localFontFiles(choice)).isNotEmpty;
  }

  /// Registers the downloaded TTFs of [choice] with the engine, if present.
  /// Safe to call on every startup; no-op when nothing is downloaded.
  Future<void> loadIfDownloaded(AppFontChoice choice) async {
    if (choice == AppFontChoice.system || _loaded.contains(choice)) return;
    final files = await _localFontFiles(choice);
    if (files.isEmpty) return;
    await _register(_specs[choice]!.family, files);
    _loaded.add(choice);
    _downloadedOnDisk.add(choice);
    notifyListeners();
  }

  /// Downloads the official font package, extracts the needed TTFs and
  /// registers them. Throws on failure (caller surfaces the error).
  Future<void> downloadAndLoad(AppFontChoice choice) async {
    final spec = _specs[choice]!;
    if (_downloading != null) return;
    _downloading = choice;
    _progress = 0;
    _receivedBytes = 0;
    _totalBytes = 0;
    notifyListeners();

    final dir = await _fontDir(choice);
    await dir.create(recursive: true);
    final zipFile = File(p.join(dir.path, '_download.zip'));

    try {
      Object? lastError;
      var ok = false;
      for (final url in spec.urls) {
        try {
          await _downloadTo(url, zipFile);
          ok = true;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (!ok) throw lastError ?? Exception('download failed');

      // Unzip off the UI thread — the packages are tens of MB.
      final extracted = await compute(_extractFonts, <String>[
        zipFile.path,
        dir.path,
        spec.entryPattern,
      ]);
      if (extracted.isEmpty) {
        throw Exception('No matching font files in the package');
      }

      await _register(spec.family, extracted.map(File.new).toList());
      _loaded.add(choice);
      _downloadedOnDisk.add(choice);
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
      _downloading = null;
      _progress = null;
      notifyListeners();
    }
  }

  Future<void> _downloadTo(String url, File target) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      _totalBytes = response.contentLength ?? 0;
      _receivedBytes = 0;
      final sink = target.openWrite();
      // Throttle listener notifications to every 256 KB — per-chunk updates
      // on a ~100 MB download would rebuild the progress dialog thousands of
      // times for no visible benefit.
      var lastNotified = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          _receivedBytes += chunk.length;
          if (_totalBytes > 0) {
            _progress = (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
          }
          if (_receivedBytes - lastNotified >= 256 * 1024) {
            lastNotified = _receivedBytes;
            notifyListeners();
          }
        }
        notifyListeners();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  Future<void> _register(String family, List<File> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        f.readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
  }
}

/// Isolate entry: extracts zip entries matching a pattern.
/// args = [zipPath, outDir, entryPattern]; returns extracted file paths.
/// De-duplicates by basename — some packages ship the same TTF in multiple
/// folders.
List<String> _extractFonts(List<String> args) {
  final zipPath = args[0];
  final outDir = args[1];
  final re = RegExp(args[2], caseSensitive: false);

  final bytes = File(zipPath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final seen = <String>{};
  final out = <String>[];
  for (final entry in archive) {
    if (!entry.isFile) continue;
    if (!re.hasMatch(entry.name)) continue;
    final name = p.basename(entry.name);
    if (!seen.add(name.toLowerCase())) continue;
    final file = File(p.join(outDir, name));
    file.writeAsBytesSync(entry.content as List<int>);
    out.add(file.path);
  }
  return out;
}
