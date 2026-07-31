# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

- Flutter **desktop** app for Windows/macOS/Linux. `android/`/`ios/` are not present; the `web/` directory is a `flutter create` artifact and is not a supported target.
- A local file-management tool that renames media files to match Jellyfin's [naming conventions](https://jellyfin.org/docs/general/server/media/naming/). It does **not** talk to Jellyfin servers — there is no API client or auth; everything is filesystem operations.
- Dart SDK `^3.10.4`. Current app version: `0.10.1+4`.

## Common commands

- `flutter pub get` — install dependencies
- `flutter run -d macos` (or `windows` / `linux`) — run the app
- `flutter gen-l10n` — regenerate localization from ARB files (`flutter run` does this automatically)
- `flutter test` — run all tests
- `flutter test test/widget_test.dart` — run a single test file (the repo currently has only one)
- `flutter analyze` — lint (uses `package:flutter_lints/flutter.yaml` per `analysis_options.yaml`)
- `flutter build macos` (or `windows` / `linux`) — release build
- Windows installer: run Inno Setup on `scripts/inno_setup.iss` after `flutter build windows`
- Windows MSIX: `dart run msix:create` builds `build/windows/x64/runner/Release/*.msix` (runs `flutter build windows` first). Config lives in the `msix_config` block of `pubspec.yaml`; `dart run msix:create --store` targets the Microsoft Store. Keep `msix_version` (a.b.c.d) in sync with `version:`.

## Architecture

### State management — two `ChangeNotifier` services wired in `lib/main.dart`

- `SettingsService` — loaded and `init()`'d before `runApp`, then registered with `ChangeNotifierProvider.value`. Persists theme mode, locale, custom search sites, and `lastSearchSiteIndex` to a JSON file in the OS app-support directory (via `path_provider`).
- `FileBrowserService` — registered with `ChangeNotifierProvider`. Owns the current directory, file list, selection, sort state (Name/Type/Date/Size, asc/desc, directories first), and a `FileSystemEvent` watcher that auto-refreshes the UI on disk changes.

The app shell is `MainWorkspace` in `lib/main.dart`, a two-tab `NavigationRail` (Manager / Settings). There is **no router** (no `go_router`); navigation is plain stateful widgets.

### Layering

- [lib/screens/media_manager_screen.dart](lib/screens/media_manager_screen.dart) — the main workflow surface. Orchestrates user actions → dialogs → service calls.
- `lib/services/` — all business logic:
  - [file_browser_service.dart](lib/services/file_browser_service.dart) — navigation, sorting, filesystem watching
  - [rename_service.dart](lib/services/rename_service.dart) — Jellyfin naming rules (static, pure functions)
  - [file_label_service.dart](lib/services/file_label_service.dart) — extension → icon/color mapping
  - [settings_service.dart](lib/services/settings_service.dart) — JSON persistence
  - [thumbnail_service.dart](lib/services/thumbnail_service.dart) — video poster frames (see below)
- `lib/widgets/file_browser/` — reusable, stateless list + toolbar widgets
- `lib/widgets/dialogs/` — modal rename workflows (`tv_show_dialog.dart`, `part_dialog.dart`, `subtitle_dialog.dart`, `search_dialog.dart`, `input_dialog.dart`). Each returns structured data (e.g. `{'result': 'S01E02', 'season': 1, 'episode': 2}`) that the calling screen feeds into `RenameService`.

### media_kit

`media_kit` is used for exactly one thing: playing a local video file inside [preview_dialog.dart](lib/widgets/dialogs/preview_dialog.dart) (a `Player` + `VideoController` + the stock `Video` widget), plus the one `MediaKit.ensureInitialized()` call in [lib/main.dart](lib/main.dart). It does **not** do metadata extraction or duration probing anywhere (thumbnails go through `fc_native_video_thumbnail`, below). Keep it that way unless there's a reason — the dependency drags in libmpv and CocoaPods on macOS (see Platform-specific notes).

Playback was evaluated against `video_player` + `video_player_win` and deliberately **not** migrated: `video_player` has no official Windows or Linux support, and `video_player_win`'s Media Foundation backend can only play what the host Windows install has codecs for — a hard regression for a tool pointed at MKV/HEVC/AV1 libraries. Don't revisit without new information.

### Thumbnails

[thumbnail_service.dart](lib/services/thumbnail_service.dart) renders video poster frames for file-table rows via `fc_native_video_thumbnail` (AVFoundation / Media Foundation / FFmpeg per platform). It is the **only cache in the app** — an in-memory LRU plus JPEGs under `<appSupport>/thumbnails/`, keyed by `sha1(path|mtime|size)` so a re-encoded file never shows a stale frame. Pruned to 64 MB, oldest-first, once per session.

Platform quirks that shaped the code: Windows ignores the `height` argument (square bounding box only) and does not seek, so the service asks for a frame at 10s and silently falls back to the first frame when that returns null or throws. Linux needs system FFmpeg + libjpeg; without them every call fails, each failure is cached per-key, and rows fall back to the type icon. Every failure path degrades to the icon — thumbnails are never load-bearing.

### Data flow

UI → dialog → service mutates filesystem → `notifyListeners()` → UI rebuilds. The filesystem is the source of truth and `FileSystemEvent` keeps the view in sync; `ThumbnailService` is the sole exception (see above).

### Localization

ARB files at `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`. `flutter: generate: true` in `pubspec.yaml` drives codegen via `l10n.yaml`. Generated `app_localizations*.dart` files live under `lib/l10n/` — **do not hand-edit them**.

## Conventions

- All path manipulation goes through the `path` package — never string concatenation. Required for cross-platform correctness.
- New rename rules belong in `lib/services/rename_service.dart` and must follow the `RenameRule` enum pattern.
- Every user-facing string must use `AppLocalizations.of(context)!.<key>` and must be added to **both** `app_en.arb` and `app_zh.arb`.
- Rename operations should be atomic and report failures via `ScaffoldMessenger`.
- UI is Material 3; respect light/dark themes and the seed-color scheme set in `lib/main.dart`.
- No `freezed` / `json_serializable` / `build_runner` in this project — JSON is hand-rolled in the services. Don't introduce codegen without a reason.

## Platform-specific notes

- **macOS sandbox:** Entitlements are split. `macos/Runner/DebugProfile.entitlements` enables JIT and a network server (needed for `flutter run`'s Dart VM); `macos/Runner/Release.entitlements` is stricter (no JIT, no network server). When adding capabilities (Bonjour, downloads folder, etc.), edit **both** files or the change won't take effect in release builds.
- **macOS still uses CocoaPods.** The pub.dev releases of `media_kit_video` (2.0.1) and `media_kit_libs_macos_video` (1.1.4) ship no `Package.swift`, so Flutter 3.44 — where Swift Package Manager is the default — falls back to CocoaPods for them. `macos/Podfile` and `macos/Podfile.lock` are **checked in and required; do not delete them**, and leave the `#include? ".../Pods-Runner.*.xcconfig"` lines in `macos/Flutter/Flutter-{Debug,Release}.xcconfig` (they must stay *above* the `ephemeral/Flutter-Generated.xcconfig` include). The build-time warning `The following plugins do not support Swift Package Manager for macos` is expected and harmless. Upstream SPM support is merged but unpublished ([media-kit#1412](https://github.com/media-kit/media-kit/pull/1412)); track [#1399](https://github.com/media-kit/media-kit/issues/1399) and [#1435](https://github.com/media-kit/media-kit/pull/1435) and drop CocoaPods once new versions land on pub.dev.
- **`intl` is pinned to `0.20.2`, not a caret range.** `flutter_localizations` from the SDK pins it exactly; `^0.20.3` makes `flutter pub get` fail version solving.
- **App identifier / org:** `joycai.cn`.
- **CI:** `.github/workflows/pr-check.yml` runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and `flutter test` on every PR to `main`. Run all three locally before pushing — an unformatted file or a lint *info* fails the build, not just errors.
