# GEMINI.md - Jellyfin Media Management Tool

This document provides context and guidelines for interacting with the Jellyfin Media Management Tool codebase.

## Project Overview

The **Jellyfin Media Management Tool** is a cross-platform **desktop** application built with Flutter (Windows/macOS/Linux only — there is no `android/`, `ios/`, or supported web target). Its purpose is to help users organize their media libraries (movies, TV shows) according to [Jellyfin's naming standards](https://jellyfin.org/docs/general/server/media/naming/). It never talks to a Jellyfin server — there is no API client and no auth; everything is local filesystem work.

The primary workflow is **AI-driven**: point the app at a folder, an LLM proposes a move/rename plan, the user reviews and edits that plan in a preview dialog, and only then does anything touch disk. Every applied batch can write an undo manifest.

### Core Technologies
- **Framework:** [Flutter](https://flutter.dev/) (Material 3), Dart SDK `^3.10.4`
- **Language:** [Dart](https://dart.dev/)
- **State Management:** [Provider](https://pub.dev/packages/provider) — seven `ChangeNotifier` services, no router
- **AI:** Plain [`http`](https://pub.dev/packages/http) calls to OpenAI-compatible (`/chat/completions`) or Google GenAI (`:generateContent`) endpoints. No vendor SDK.
- **Media Engine:** [Media Kit](https://media-kit.github.io/) (based on libmpv) — used solely for playing local video files inside the preview dialog. It is not used for metadata extraction.
- **Thumbnails:** [`fc_native_video_thumbnail`](https://pub.dev/packages/fc_native_video_thumbnail) (AVFoundation / Media Foundation / FFmpeg per platform)
- **Localization:** Flutter `intl` and ARB files for multi-language support (English & Chinese).
- **Storage:** Local JSON in the OS application-support directory — `config.json` (settings), `ai_profiles.json` (AI endpoints and keys), `sites.json` (search sites), `undo/op-*.json` (undo manifests), plus the `thumbnails/` and `fonts/` caches.

### Key Features
- **AI Organize Pipeline:** Scan a folder, get an LLM-proposed rename/move plan, edit it, apply it. The preview dialog is the only dry-run and the only gate.
- **Undo History:** Each applied batch writes a manifest that can be reversed; manifests are pruned after 7 days.
- **Tasks:** Long-running analyze and apply operations run as cancellable, pausable background tasks with their own tab.
- **File Browser:** Advanced navigation with smart sorting, multi-selection, video thumbnails, and real-time directory monitoring.
- **Media Preview:** Rich previews for video (inline playback), images, and text (subtitles/NFO).
- **Web Search:** Configurable search sites for looking up media information in an external browser.

## Project Structure

```text
lib/
├── main.dart                 # Entry point: service init order, providers, theme.
├── l10n/                     # Localization resources (app_en.arb, app_zh.arb) and generated files.
├── models/                   # Plain data classes (organize_plan.dart, file_entry.dart, ...).
├── screens/
│   └── home_screen.dart      # The app shell: header + sidebar | table | AI panel.
├── shortcuts/
│   └── app_shortcuts.dart    # Single source of truth for every keyboard binding.
├── services/                 # Business logic and state management.
│   ├── ai/                   # Providers, prompt building, HTTP retry, cancellation.
│   ├── ai_service.dart       # Live AI config, connection status, the current OrganizePlan.
│   ├── ai_profiles_service.dart # Named AI endpoint profiles.
│   ├── apply_controller.dart # Drives a plan to disk with pause/stop.
│   ├── organize_service.dart # applyOrganizeAction — the single chokepoint for moves.
│   ├── history_service.dart  # Undo manifests.
│   ├── path_safety.dart      # Containment checks for every write.
│   ├── task_service.dart     # Background analyze/apply tasks.
│   ├── file_browser_service.dart # Navigation, sorting, selection, FS watching.
│   ├── settings_service.dart # App configuration, theme, and localization.
│   ├── thumbnail_service.dart# Video poster frames (the app's only cache).
│   ├── file_label_service.dart# Utilities for file type identification and icon mapping.
│   └── rename_service.dart   # Legacy — see below.
├── theme/app_theme.dart      # M3 themes plus the GlassTheme ThemeExtension.
└── widgets/                  # Reusable UI components.
    ├── ai/                   # Assistant panel, preview dialog, progress and history screens.
    ├── file_browser/         # Media table, context menu, thumbnails.
    ├── dialogs/              # Preview, title hint, and legacy rename dialogs.
    └── sidebar/ settings/ tasks/ onboarding/ glass/
```

`test/` mirrors `lib/` (`models/`, `services/`, `utils/`, `widgets/`).

### Legacy Code

`lib/services/rename_service.dart` predates the AI pipeline and is now nearly dead. Its only consumer is `lib/widgets/ai/edit_action_dialog.dart`, which calls `buildName` and `baseNameForTarget` to suggest a corrected filename; `getNewName(File, ...)` and `rename(File, ...)` have no call sites. Do **not** treat it as the place new organizing logic belongs. The one rule worth preserving if it is ever deleted: `baseNameForTarget` walks *past* `Season NN` / `Specials` container folders up to the series folder, or TV renames produce `Season 01.S01E01.mkv`.

`lib/widgets/dialogs/{tv_show,part,subtitle}_dialog.dart` are likewise remnants of the old manual rename workflow.

## Building and Running

### Prerequisites
- Flutter SDK (Dart `^3.10.4`)
- **libmpv** is required for video preview playback. On Windows and macOS it is bundled by `media_kit_libs_video`; on Linux it must be installed system-wide (e.g. `apt install libmpv-dev mpv`).
- Linux thumbnails additionally need system FFmpeg and libjpeg; without them rows fall back to the file-type icon.
- macOS builds still go through **CocoaPods** for `media_kit`. `macos/Podfile` and `macos/Podfile.lock` are checked in and required — do not delete them.

### Common Commands
- **Install Dependencies:** `flutter pub get`
- **Run Application:** `flutter run -d <windows|macos|linux>`
- **Generate L10n:** `flutter gen-l10n` (usually handled automatically by `flutter run`)
- **Test:** `flutter test`, or a single file with `flutter test test/services/organize_service_test.dart`
- **Format & Lint:** `dart format lib/ test/` and `flutter analyze --fatal-infos`
- **Build Release:**
  - Windows: `flutter build windows`
  - macOS: `flutter build macos`
  - Linux: `flutter build linux`

CI (`.github/workflows/pr-check.yml`) runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, and `flutter test` on every PR to `main`. A lint *info* fails the build, not just an error — run all three locally before pushing.

## Development Conventions

### UI & Styling
- Strictly adhere to **Material 3** design principles.
- Use `ColorScheme` from seed colors for consistent branding, honouring the user's accent choice.
- Read frosted-panel values through `Theme.of(context).extension<GlassTheme>()!` rather than hardcoding colors.
- Support both **Light** and **Dark** themes.
- Ensure the layout is responsive for desktop window resizing. A minimum of 1024x700 is enforced via `window_manager`; the side panes are fixed-width (244 + 352).

### State Management
- Use `ChangeNotifier` and `Provider` for reactive state updates.
- Keep UI components (widgets) as lean as possible, delegating logic to services.
- Service init order in `main()` is load-bearing: `AiProfilesService.init()` must run before `SettingsService.init()`, and `FontService` must finish before `runApp`.
- Only **one** `OrganizePlan` exists app-wide, owned by `AiService`. A second analyze replaces it — concurrent analyses are last-writer-wins.

### Organizing & Filesystem Writes
- New organizing logic belongs in the AI pipeline — prompt shaping in `lib/services/ai/ai_prompt.dart`, plan parsing in `lib/models/organize_plan.dart`, application in `lib/services/organize_service.dart`. Not in `rename_service.dart`.
- **Every write to disk must go through `applyOrganizeAction`** or justify why not, and must validate with `PathSafety.isWithin`. It refuses to clobber existing targets, falls back to copy+delete across volumes, and records per-action status instead of aborting the batch.
- Nothing may touch disk before the user confirms `OrganizePreviewDialog`. Keep `OrganizeAction.target` mutable so the dialog can correct the model in memory.
- The model must echo `relativePath` back verbatim as `source`; changing the prompt's path handling means changing both ends.
- Failures are reported via `ScaffoldMessenger`; batch operations report counts, not just the first error.

### Keyboard Shortcuts
- All bindings live in `lib/shortcuts/app_shortcuts.dart` as the **single source of truth**. `HomeScreen` builds its `CallbackShortcuts` map from it and the Settings → Shortcuts page renders its table from the same list.
- Add a new shortcut as one entry there — never a bare `SingleActivator` inside a widget.
- Activators are platform-aware (⌘ on macOS, Ctrl elsewhere) and the displayed notation is derived from the activator, not hardcoded.
- Set `skipWhileTyping` on anything that would otherwise steal a key from a focused text field (Ctrl+A, Delete, F2, ...).

### Localization
- All user-facing strings MUST be localized using `AppLocalizations.of(context)`.
- When adding new strings, update both `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`.
- Generated `app_localizations*.dart` files live under `lib/l10n/` — do not hand-edit them.

### File Handling
- Use the `path` package for all path manipulations to ensure cross-platform compatibility.
- Prefer `FileSystemEntity` for generic file/directory operations.
- Code that writes should accept a `FileSystem` (package `file`) where practical, so tests can run against an in-memory filesystem — see `test/services/organize_service_test.dart`.
- No `freezed` / `json_serializable` / `build_runner`: JSON is hand-rolled in the services. Don't introduce codegen without a reason.
