# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

- Flutter **desktop** app for Windows/macOS/Linux. `android/`/`ios/` are not present; the `web/` directory is a `flutter create` artifact and is not a supported target.
- A local file-management tool that renames media files to match Jellyfin's [naming conventions](https://jellyfin.org/docs/general/server/media/naming/). It does **not** talk to Jellyfin servers — there is no API client or auth; everything is filesystem operations.
- Dart SDK `^3.10.4`. Current app version: `0.9.1+2`.

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
- `lib/widgets/file_browser/` — reusable, stateless list + toolbar widgets
- `lib/widgets/dialogs/` — modal rename workflows (`tv_show_dialog.dart`, `part_dialog.dart`, `subtitle_dialog.dart`, `search_dialog.dart`, `input_dialog.dart`). Each returns structured data (e.g. `{'result': 'S01E02', 'season': 1, 'episode': 2}`) that the calling screen feeds into `RenameService`.

### Data flow

UI → dialog → service mutates filesystem → `notifyListeners()` → UI rebuilds. No caching layer; the filesystem is the source of truth and `FileSystemEvent` keeps the view in sync.

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
- **App identifier / org:** `joycai.cn`.
- **No CI/CD:** `.github/workflows/` was removed. Builds and releases are manual.
