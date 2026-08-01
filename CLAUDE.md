# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

- Flutter **desktop** app for Windows/macOS/Linux. `android/`/`ios/` are not present; the `web/` directory is a `flutter create` artifact and is not a supported target.
- A local file-management tool that organizes media libraries to match Jellyfin's [naming conventions](https://jellyfin.org/docs/general/server/media/naming/). It does **not** talk to Jellyfin servers — there is no API client or auth; everything is filesystem operations.
- The primary workflow is **AI-driven**: point it at a folder, an LLM proposes a move/rename plan, the user reviews and edits the plan in a preview dialog, and only then does anything touch disk. Every applied batch writes an undo manifest.
- Dart SDK `^3.10.4`. Current app version: `0.12.0+6`.

## Common commands

- `flutter pub get` — install dependencies
- `flutter run -d windows` (or `macos` / `linux`) — run the app
- `flutter gen-l10n` — regenerate localization from ARB files (`flutter run` does this automatically)
- `flutter test` — run all tests (`test/` mirrors `lib/`: `models/`, `services/`, `utils/`, `widgets/`)
- `flutter test test/services/organize_service_test.dart` — run a single test file
- `flutter analyze` — lint (uses `package:flutter_lints/flutter.yaml` per `analysis_options.yaml`)
- `flutter build windows` (or `macos` / `linux`) — release build
- Windows installer: run Inno Setup on `scripts/inno_setup.iss` after `flutter build windows`
- Windows MSIX: `dart run msix:create` builds `build/windows/x64/runner/Release/*.msix` (runs `flutter build windows` first). Config lives in the `msix_config` block of `pubspec.yaml`; `dart run msix:create --store` targets the Microsoft Store. Keep `msix_version` (a.b.c.d) in sync with `version:`.
- Version bumps: use the `sync-version` skill (`.claude/skills/sync-version/`) — the version is hardcoded in four places and they drift otherwise.

## Architecture

### App shell

`lib/main.dart` initializes services then runs `MyApp` → `HomeScreen` (or `OnboardingScreen` until `settings.onboardingSeen`). There is **no router** (no `go_router`); full-page surfaces (Settings, History, task detail) are plain `Navigator.push`, and everything else is a dialog.

[home_screen.dart](lib/screens/home_screen.dart) is the shell: a full-width header (brand · section tabs · search · actions) over a three-pane body — `AppSidebar` (244px) | `MediaTable` (flex) | `AiAssistantPanel` (352px). Three sections: Files, Library (placeholder), Tasks.

**Init order in `main()` matters.** `AiProfilesService.init()` must run *before* `SettingsService.init()` — it performs a one-time migration out of the legacy `config.json` AI keys, and `SettingsService` would otherwise rewrite that file without them. `FontService.init()` + `loadIfDownloaded()` must complete before `runApp` or the first frame flashes the system font.

### Services

Seven `ChangeNotifier`s are registered in `lib/main.dart`:

| Service | Owns |
|---|---|
| [settings_service.dart](lib/services/settings_service.dart) | Theme, locale, accent, glass intensity, font choice, favorites, recents (cap 8), onboarding flag → `config.json`; search sites → `sites.json` |
| [ai_profiles_service.dart](lib/services/ai_profiles_service.dart) | Named AI endpoint profiles + active id → `ai_profiles.json` |
| [ai_service.dart](lib/services/ai_service.dart) | Live `AiConfig`, connection status, **the single current `OrganizePlan`**, usage stats |
| [file_browser_service.dart](lib/services/file_browser_service.dart) | Current directory, file list, focus + multi-selection, sort state, `FileSystemEvent` watcher |
| [task_service.dart](lib/services/task_service.dart) | The Tasks-tab list of running/finished analyze + apply tasks |
| [history_service.dart](lib/services/history_service.dart) | Undo manifests under `undo/op-*.json`, 7-day retention |
| [font_service.dart](lib/services/font_service.dart) | Optional downloadable CJK UI fonts (HarmonyOS Sans SC, MiSans) |

[apply_controller.dart](lib/services/apply_controller.dart) is also a `ChangeNotifier` but is **not** registered — one instance is created per apply and owned by its `OrganizerTask`.

Pure/plain (no Provider): the `AiProvider` implementations, `AiHttp`, `AiCancelToken`, `AiPrompt`, [path_safety.dart](lib/services/path_safety.dart), [organize_service.dart](lib/services/organize_service.dart) (a single top-level function), and all models.

### The organize pipeline

This is the core flow; understand it before touching anything under `lib/services/ai/` or `lib/widgets/ai/`.

1. **Trigger** — `_organize()` in [home_screen.dart](lib/screens/home_screen.dart). An empty multi-selection means "the whole folder"; a non-empty one restricts the scan.
2. **Hint** — `showTitleHintDialog` collects an optional canonical title and a movie/series/auto hint.
3. **Task** — `TaskService.startAnalyze(...)` mints an `AiCancelToken`, inserts a running task, and fires `AiService.analyzeFolder` unawaited. The Tasks tab badge tracks `runningCount`.
4. **Analyze** — `AiService.analyzeFolder` walks the tree (**capped at 400 files**, dotfiles skipped), builds prompts via `AiPrompt`, and calls the active provider.
5. **Provider** — `OpenAiProvider` (`/chat/completions`, JSON mode) or `GoogleGenAiProvider` (`:generateContent`), both through `AiHttp.withRetry` on the cancel token's client, 120s timeout.
6. **Parse** — `OrganizePlan.fromAiJson` produces `OrganizeAction`s. Confidence `< 0.6` → `ActionStatus.needsReview`.
7. **Preview — this is the only dry-run and the only gate.** The AI panel's button says *Preview*, not *Apply*. `OrganizePreviewDialog` lets the user edit `action.target` in place and toggle the undo checkbox, and returns `({bool apply, bool backup})`. Cancel means nothing touched disk.
8. **Apply** — `ApplyController.start()` loops the plan honoring pause/stop, **skipping `needsReview` actions entirely**, calling `applyOrganizeAction` per action.
9. **History** — iff `backup` and at least one move succeeded, a manifest is written for undo.

**Non-obvious invariants:**

- **Only one plan exists app-wide.** A second `analyzeFolder` nulls the current plan immediately — concurrent analyze tasks are last-writer-wins.
- **`backup` does not copy anything.** It gates whether an undo manifest is recorded. The name is a misnomer kept for the UI string.
- **`OrganizeAction.target` is deliberately mutable** so the preview dialog can correct the model in memory. This keeps every disk write behind `ApplyController`.
- **The model must echo `relativePath` back verbatim as `source`** — that contract is what lets `applyOrganizeAction` re-join it to `baseDir`. Don't change the prompt's path handling without checking both ends.
- **Cancellation works by closing the token's own `http.Client`**, so cancellable requests must not use the shared `AiHttp.client`. A socket close surfaces as a generic `ClientException` and is re-mapped to `AiCancelled`.
- `AiService.updateConfig` is called from a widget `build()`, so it early-returns when unchanged and defers `notifyListeners` via a post-frame callback. Breaking either causes "setState() during build".

### Filesystem writes

**`applyOrganizeAction` in [organize_service.dart](lib/services/organize_service.dart) is the single chokepoint for moves.** It:

- validates both source and target with `PathSafety.isWithin(baseDir, ...)` — pass `context:` so an injected in-memory POSIX filesystem isn't parsed with Windows rules;
- refuses to clobber an existing target, except for case-only renames;
- falls back to copy+delete across volumes, and deletes the copy if the source delete fails so no silent duplicate is left;
- mutates `action.status`/`action.error` and never aborts the batch on one failure.

It takes a `FileSystem` (package `file`) so tests can run against an in-memory FS — see `test/services/organize_service_test.dart`.

### Undo

[history_service.dart](lib/services/history_service.dart) writes one JSON manifest per operation to `<appSupport>/undo/op-<millis>.json`. `undo()` reverses moves **in reverse order** (so child folders empty before parents), re-checks `PathSafety` against the manifest's `baseDir` as defense against tampering, and treats an already-present source as success. Full success deletes the manifest; **partial success rewrites it with only the unrecovered moves** so a retry makes progress. `refresh()` prunes manifests older than `retentionDays = 7` — that pruning is the entire implementation of the UI's 7-day promise. Note it does not remove directories the apply created.

### Persistence

Everything lives in the `path_provider` application-support directory, hand-rolled JSON in the owning service:

- `config.json` — settings (debounced 250ms, flushed on dispose)
- `ai_profiles.json` — AI profiles and API keys, deliberately separate so a slider drag never rewrites keys
- `sites.json` — custom search sites
- `undo/op-*.json` — undo manifests
- `thumbnails/*.jpg` — the thumbnail cache
- `fonts/<id>/*.ttf` — downloaded UI fonts

### Keyboard shortcuts

All bindings live in [lib/shortcuts/app_shortcuts.dart](lib/shortcuts/app_shortcuts.dart) as a **single source of truth**: each entry pairs an activator with an l10n description key and an intent. `HomeScreen` builds its `CallbackShortcuts` map from it and the Settings → Shortcuts page renders its table from the same list, so a new shortcut is one entry, not three edits. Activators are platform-aware (`meta:` on macOS, `control:` elsewhere) and the displayed notation follows.

### media_kit

`media_kit` is used for exactly one thing: playing a local video file inside [preview_dialog.dart](lib/widgets/dialogs/preview_dialog.dart) (a `Player` + `VideoController` + the stock `Video` widget), plus the one `MediaKit.ensureInitialized()` call in [lib/main.dart](lib/main.dart). It does **not** do metadata extraction or duration probing anywhere (thumbnails go through `fc_native_video_thumbnail`, below). Keep it that way unless there's a reason — the dependency drags in libmpv and CocoaPods on macOS (see Platform-specific notes).

Playback was evaluated against `video_player` + `video_player_win` and deliberately **not** migrated: `video_player` has no official Windows or Linux support, and `video_player_win`'s Media Foundation backend can only play what the host Windows install has codecs for — a hard regression for a tool pointed at MKV/HEVC/AV1 libraries. Don't revisit without new information.

### Thumbnails

[thumbnail_service.dart](lib/services/thumbnail_service.dart) renders video poster frames for file-table rows via `fc_native_video_thumbnail` (AVFoundation / Media Foundation / FFmpeg per platform). It is the **only cache in the app** — an in-memory LRU plus JPEGs under `<appSupport>/thumbnails/`, keyed by `sha1(path|mtime|size)` so a re-encoded file never shows a stale frame. Pruned to 64 MB, oldest-first, once per session.

Platform quirks that shaped the code: Windows ignores the `height` argument (square bounding box only) and does not seek, so the service asks for a frame at 10s and silently falls back to the first frame when that returns null or throws. Linux needs system FFmpeg + libjpeg; without them every call fails, each failure is cached per-key, and rows fall back to the type icon. Every failure path degrades to the icon — thumbnails are never load-bearing.

### Theming

[app_theme.dart](lib/theme/app_theme.dart) builds Material 3 light/dark themes from an optional user accent seed, and carries a `GlassTheme` `ThemeExtension` (backdrop gradient, sidebar fill, blur intensity) that the frosted panels read. Read glass values through `Theme.of(context).extension<GlassTheme>()!`, never by hardcoding colors.

### Localization

ARB files at `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`. `flutter: generate: true` in `pubspec.yaml` drives codegen via `l10n.yaml`. Generated `app_localizations*.dart` files live under `lib/l10n/` — **do not hand-edit them**.

### Legacy

[rename_service.dart](lib/services/rename_service.dart) predates the AI pipeline and is now nearly dead: its only consumer is [edit_action_dialog.dart](lib/widgets/ai/edit_action_dialog.dart), which uses `buildName` and `baseNameForTarget` to suggest a corrected filename. `getNewName(File, ...)` and `rename(File, ...)` have no call sites. The one rule worth preserving if it's ever removed: `baseNameForTarget` walks *past* `Season NN` / `Specials` container folders up to the series folder, otherwise TV renames produce `Season 01.S01E01.mkv`.

Similarly, `lib/widgets/dialogs/{tv_show,part,subtitle}_dialog.dart` are remnants of the old manual rename workflow.

Three persisted settings toggles — `autoConnectAi`, `alwaysShowPreview`, `lowConfidenceSuggestOnly` — are read only by the settings UI and have **no effect on runtime behavior**. The preview is always shown; low-confidence handling is hardcoded in `OrganizeAction`.

## Conventions

- All path manipulation goes through the `path` package — never string concatenation. Required for cross-platform correctness.
- Any code that writes to disk must go through `applyOrganizeAction` or justify why not, and must validate with `PathSafety.isWithin`.
- Every user-facing string must use `AppLocalizations.of(context)!.<key>` and must be added to **both** `app_en.arb` and `app_zh.arb`.
- New keyboard shortcuts go in `lib/shortcuts/app_shortcuts.dart` — do not add a bare `SingleActivator` in a widget.
- Failures are reported via `ScaffoldMessenger`; batch operations report counts, not just the first error.
- UI is Material 3; respect light/dark themes, the accent seed, and `GlassTheme`.
- No `freezed` / `json_serializable` / `build_runner` in this project — JSON is hand-rolled in the services. Don't introduce codegen without a reason.

## Platform-specific notes

- **macOS sandbox:** Entitlements are split. `macos/Runner/DebugProfile.entitlements` enables JIT and a network server (needed for `flutter run`'s Dart VM); `macos/Runner/Release.entitlements` is stricter (no JIT, no network server). When adding capabilities (Bonjour, downloads folder, etc.), edit **both** files or the change won't take effect in release builds.
- **macOS still uses CocoaPods.** The pub.dev releases of `media_kit_video` (2.0.1) and `media_kit_libs_macos_video` (1.1.4) ship no `Package.swift`, so Flutter 3.44 — where Swift Package Manager is the default — falls back to CocoaPods for them. `macos/Podfile` and `macos/Podfile.lock` are **checked in and required; do not delete them**, and leave the `#include? ".../Pods-Runner.*.xcconfig"` lines in `macos/Flutter/Flutter-{Debug,Release}.xcconfig` (they must stay *above* the `ephemeral/Flutter-Generated.xcconfig` include). The build-time warning `The following plugins do not support Swift Package Manager for macos` is expected and harmless. Upstream SPM support is merged but unpublished ([media-kit#1412](https://github.com/media-kit/media-kit/pull/1412)); track [#1399](https://github.com/media-kit/media-kit/issues/1399) and [#1435](https://github.com/media-kit/media-kit/pull/1435) and drop CocoaPods once new versions land on pub.dev.
- **`intl` is pinned to `0.20.2`, not a caret range.** `flutter_localizations` from the SDK pins it exactly; `^0.20.3` makes `flutter pub get` fail version solving.
- **Minimum window size is enforced at 1024x700** via `window_manager` in `main()`. The panes are fixed-width (244 + 352), so below that the center pane collapses and the header overflows.
- **Google GenAI sends the API key in the query string**, not a header. Keep it out of logs.
- **App identifier / org:** `joycai.cn`.
- **CI:** `.github/workflows/pr-check.yml` runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and `flutter test` on every PR to `main`. Run all three locally before pushing — an unformatted file or a lint *info* fails the build, not just errors.
