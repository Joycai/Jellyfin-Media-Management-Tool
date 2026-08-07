# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

- Flutter **desktop** app for Windows/macOS/Linux. `android/`/`ios/` are not present; the `web/` directory is a `flutter create` artifact and is not a supported target.
- A local file-management tool that organizes media libraries to match Jellyfin's [naming conventions](https://jellyfin.org/docs/general/server/media/naming/). It does **not** talk to Jellyfin servers — there is no API client or auth; everything is filesystem operations.
- The primary workflow is **AI-driven**: point it at a folder, an LLM proposes a move/rename plan, the user reviews and edits the plan in a preview dialog, and only then does anything touch disk. Every applied batch writes an undo manifest.
- Dart SDK `^3.10.4`. Current app version: `0.13.0+7`.

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

Nine `ChangeNotifier`s are registered in `lib/main.dart`:

| Service | Owns |
|---|---|
| [settings_service.dart](lib/services/settings_service.dart) | Theme, locale, accent, glass intensity, font choice, favorites, recents (cap 8), onboarding flag → `config.json`; search sites → `sites.json` |
| [ai_profiles_service.dart](lib/services/ai_profiles_service.dart) | Named AI endpoint profiles + active id → `ai_profiles.json` |
| [ai_service.dart](lib/services/ai_service.dart) | Live `AiConfig`, connection status, **the single current `OrganizePlan`**, usage stats |
| [file_browser_service.dart](lib/services/file_browser_service.dart) | Current directory, file list, focus + multi-selection, sort state, `FileSystemEvent` watcher |
| [task_service.dart](lib/services/task_service.dart) | The Tasks-tab list of running/finished analyze + apply tasks |
| [history_service.dart](lib/services/history_service.dart) | Undo manifests under `undo/op-*.json`, 7-day retention |
| [font_service.dart](lib/services/font_service.dart) | Optional downloadable CJK UI fonts (HarmonyOS Sans SC, MiSans) |
| [recipe_store.dart](lib/services/scrape/recipe_store.dart) | Learned / user-edited scrape recipes → `scrapers.json`, plus per-recipe health counters |
| [scrape_service.dart](lib/services/scrape/scrape_service.dart) | One scrape at a time: fetch → extract → merge plan → commit |

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

[history_service.dart](lib/services/history_service.dart) writes one JSON manifest per operation to `<appSupport>/undo/op-<millis>.json`. A manifest describes three kinds of reversible work, and `undo()` handles all three:

- `moves` — reversed **in reverse order** (so child folders empty before parents); an already-present source counts as success.
- `created` — files the operation brought into existence, deleted on undo. This and the next are what a scrape commit records.
- `restored` — files it overwrote, mapped to a real copy of the original under `<appSupport>/undo/blobs/<opId>/`, copied back on undo.

Every path is re-checked with `PathSafety` as defense against a tampered manifest: move and `created` paths against the manifest's `baseDir`, and a `restored` **source against the undo directory** — without that last one a hand-edited manifest could name any file on disk as a "backup" and have its contents copied into the library.

Full success deletes the manifest *and* its blob directory; **partial success rewrites it with only the unrecovered work** so a retry makes progress. `refresh()` prunes manifests older than `retentionDays = 7` and blob directories by their newest contained file — that pruning is the entire implementation of the UI's 7-day promise, and the blob half of it is what stops backups growing without bound. Note undo does not remove directories the operation created.

The service does all path work through `_fs.path` and passes `context:` to `PathSafety`, so an injected in-memory POSIX filesystem isn't parsed with Windows rules — the same obligation `applyOrganizeAction` and `MetadataWriter` carry.

### Metadata scraping

A second pipeline, parallel to organize and sharing only `AiProvider`. Point it at a product-page URL; it extracts title / code / synopsis / cast / artwork, shows a reviewable diff against any NFO already on disk, and only then writes. Design notes and the verified GIGA analysis are in [docs/spec/scrape-module-spec.md](docs/spec/scrape-module-spec.md) and [docs/spec/scrape-giga-recipe.md](docs/spec/scrape-giga-recipe.md).

**It is deliberately not routed through `OrganizePlan`.** Only one plan exists app-wide and a second `analyzeFolder` nulls it, so a stray Organize click would discard metadata the user had not committed yet.

Extraction is a four-tier ladder, cheapest first:

1. `structured_data.dart` — JSON-LD / OpenGraph. Free, and **always validated by `isSiteWideTemplate` first**: plenty of sites emit one static OpenGraph block for the whole domain, and trusting it gives every title in a library identical metadata. A recipe can disable the tier outright with `skipStructuredData`.
2. `recipe_applier.dart` — a declarative `ScrapeRecipe` (built-in, learned, or hand-edited). Free.
3. `recipe_learner.dart` — the LLM writes a recipe. Only reached when tier 2 had no recipe to run and the caller passed a `RecipeLearner`, so a site with a working recipe never costs a token. `html_cleaner.dart` strips the page to a selector-only skeleton first (scripts, styling and most text gone; ~200 KB → 20–30 KB), and `scrape_prompt.dart` asks for **selectors, not content**, using the built-in GIGA recipe as its worked example so the few-shot can never drift from the schema the parser accepts. Every attempt is self-checked by running the new recipe against the same page; a shortfall is fed back for one retry, then it gives up.
4. The user pastes page HTML (`ScrapeService.scrapeHtml`) — same pipeline from there on.

**A learned recipe is never saved automatically.** `ScrapeService` returns it on `ScrapeResult.learnedRecipe` and only the preview dialog's confirmation puts it in `RecipeStore`. The reason is in [scrape-giga-recipe.md](docs/spec/scrape-giga-recipe.md) §2.3: GIGA's synopsis exists twice, folded and expanded, and a model that grabs the folded copy yields a recipe that runs, returns non-empty values and looks entirely healthy while storing truncated text for every title on the site. The self-check can only catch *empty* fields, never short ones — which is exactly why the decision has to be a human's. Everything the learned recipe extracted is stamped `FieldOrigin.llm` so the preview flags it in amber.

`ScrapeRecipe` supports two extraction shapes. `fields` is one CSS selector per field; `keyValue` walks a `dl/dt/dd` table and maps the *label text* to a field. **Prefer `keyValue` where a page has one** — a label like `作品番号` survives a redesign that renames every CSS class. Selector lists are priority-ordered fallbacks, which is how "prefer the expanded synopsis over the truncated one" is expressed as data.

`page_fetcher.dart` is the only code that talks to a scraped site: it owns encoding detection (`http`'s latin1 default mangles Japanese pages — see `html_decoding.dart`), the cookie header, `Referer` on image downloads, and a per-host request queue with a minimum interval.

Cookies come from two places, in this order: the static string in a recipe (`old_check=yes` for GIGA's age gate — no login, no session, no expiry) and a user-imported Netscape `cookies.txt`. `CookieStore` is pure and in-memory; a browser export can contain a session ID equivalent to being logged in, so persisting it is an explicit decision for the owning service, guarded like `ai_profiles.json`.

**`MetadataWriter` is the second filesystem chokepoint**, alongside `applyOrganizeAction`. It carries the same obligations (`PathSafety.isWithin` with `context:`, `path` package only, one failure never aborts the batch) but not the same contract — `applyOrganizeAction` relocates an existing file and refuses to clobber, this writes new content and sometimes must overwrite. **`backup` here really copies**, unlike everywhere else in the app: overwriting an NFO is not reversible by moving a file back.

`NfoWriter` only replaces the elements in `managedElements`; anything else in an existing NFO (another scraper's tags, watch state, hand corrections) is copied through verbatim. `NfoMerge` produces the per-field keep/replace/merge plan, defaulting to **fill blanks automatically, keep conflicts** — adding information is safe, replacing it is a judgement call — and never lets an LLM-sourced value overwrite an existing one.

The UI flow lives in [scrape_flow.dart](lib/widgets/scrape/scrape_flow.dart), shared by the context menu and the `Ctrl/⌘+M` shortcut the way `renameEntry` is: URL dialog → `TaskService.startScrape` → a SnackBar offering the review → `ScrapePreviewDialog` → `TaskService.startScrapeCommit`. **Only the commit task writes anything**; cancelling the preview leaves the disk untouched, exactly as in the organize pipeline.

A **folder refresh** is the batch form, on a directory's context menu. It is deliberately *not* "scrape this whole folder from scratch": `NfoWriter` leaves a `<!-- scraped from … -->` comment and `NfoReader` reads it back, so a refresh re-fetches exactly the pages the app already knows about. An NFO from another tool has no such comment and is not a candidate — there is nothing to guess from, and inventing a per-site search would be a different feature.

The batch applies each title's **default** merge plan (blanks filled, conflicts kept, lists merged) with no per-title diff: three hundred dialogs is a fatigue test, not review. The gate is the confirmation dialog, which states that policy, lists what will be touched, and lets rows be deselected. Artwork is off by default — the images landed on the first scrape. One manifest covers the whole batch, since that is the operation the user thinks they performed. `rescrapeAll` is serial on purpose: `PageFetcher` enforces a per-host interval anyway, so concurrency would only queue inside the fetcher while making the progress bar lie.

`test/fixtures/giga_product_7743.html` is real (trimmed) markup and pins the two traps that page contains — duplicated `id` attributes, and folded/expanded copies of the same text where picking the wrong one yields a plausible but silently truncated result.

The preview's backup checkbox gates both halves of undo: the real copies into `<appSupport>/undo/blobs/scrape-<millis>/` and the `HistoryService.recordScrape` manifest that says what to reverse. Unchecked means neither, so the write is not undoable — which is what the label says.

Not done yet: the Library section (still the `_ComingSoon` placeholder), recipe import/export, and feeding a scraped title/year into `AiPrompt` as an organize hint.

### Persistence

Everything lives in the `path_provider` application-support directory, hand-rolled JSON in the owning service:

- `config.json` — settings (debounced 250ms, flushed on dispose)
- `ai_profiles.json` — AI profiles and API keys, deliberately separate so a slider drag never rewrites keys
- `sites.json` — custom search sites
- `scrapers.json` — learned / user-edited scrape recipes (built-ins live in code)
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
- `xml` is pinned to `^6`, not `^7`: it was already in the lock file transitively via `msix` at 6.6.1, and a `^7` caret fails version solving the same way `intl: ^0.20.3` does.
- No `freezed` / `json_serializable` / `build_runner` in this project — JSON is hand-rolled in the services. Don't introduce codegen without a reason.

## Platform-specific notes

- **macOS sandbox:** Entitlements are split. `macos/Runner/DebugProfile.entitlements` enables JIT and a network server (needed for `flutter run`'s Dart VM); `macos/Runner/Release.entitlements` is stricter (no JIT, no network server). When adding capabilities (Bonjour, downloads folder, etc.), edit **both** files or the change won't take effect in release builds.
- **macOS still uses CocoaPods.** The pub.dev releases of `media_kit_video` (2.0.1) and `media_kit_libs_macos_video` (1.1.4) ship no `Package.swift`, so Flutter 3.44 — where Swift Package Manager is the default — falls back to CocoaPods for them. `macos/Podfile` and `macos/Podfile.lock` are **checked in and required; do not delete them**, and leave the `#include? ".../Pods-Runner.*.xcconfig"` lines in `macos/Flutter/Flutter-{Debug,Release}.xcconfig` (they must stay *above* the `ephemeral/Flutter-Generated.xcconfig` include). The build-time warning `The following plugins do not support Swift Package Manager for macos` is expected and harmless. Upstream SPM support is merged but unpublished ([media-kit#1412](https://github.com/media-kit/media-kit/pull/1412)); track [#1399](https://github.com/media-kit/media-kit/issues/1399) and [#1435](https://github.com/media-kit/media-kit/pull/1435) and drop CocoaPods once new versions land on pub.dev.
- **`intl` is pinned to `0.20.2`, not a caret range.** `flutter_localizations` from the SDK pins it exactly; `^0.20.3` makes `flutter pub get` fail version solving.
- **Minimum window size is enforced at 1024x700** via `window_manager` in `main()`. The panes are fixed-width (244 + 352), so below that the center pane collapses and the header overflows.
- **Google GenAI sends the API key in the query string**, not a header. Keep it out of logs.
- **App identifier / org:** `joycai.cn`.
- **CI:** `.github/workflows/pr-check.yml` runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and `flutter test` on every PR to `main`. Run all three locally before pushing — an unformatted file or a lint *info* fails the build, not just errors.
