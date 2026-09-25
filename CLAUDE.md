# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

It states the rules in a line each. The reasons, measurements and history behind them are in [`docs/architecture/`](docs/architecture/) — read the matching file before changing a subsystem, and update both in the same commit when a rule changes.

## Project overview

- Flutter **desktop** app for Windows/macOS/Linux. There are no `android/`, `ios/` or `web/` directories — those targets are not supported, and `flutter create` scaffolding for them should not be re-added.
- A local file-management tool that organizes media libraries to match Jellyfin's [naming conventions](https://jellyfin.org/docs/general/server/media/naming/). It does **not** talk to Jellyfin servers — there is no API client or auth; everything is filesystem operations.
- The primary workflow is **AI-driven**: point it at a folder, an LLM proposes a move/rename plan, the user reviews and edits the plan in a preview dialog, and only then does anything touch disk. Every applied batch writes an undo manifest.
- Dart SDK `^3.10.4`. Current app version: `1.3.0+4`.

## Common commands

- `flutter pub get` — install dependencies
- `flutter run -d windows` (or `macos` / `linux`) — run the app
- `flutter gen-l10n` — regenerate localization from ARB files (`flutter run` does this automatically)
- `flutter test` — run all tests; `flutter test test/services/organize/organize_service_test.dart` runs one file
- `flutter analyze --fatal-infos` — lint exactly as CI does (`flutter_lints` plus the rules in `analysis_options.yaml`)
- `dart format .` — format; CI checks with `--set-exit-if-changed`
- `flutter build windows` (or `macos` / `linux`) — release build
- Windows installer: run Inno Setup on `scripts/inno_setup.iss` after `flutter build windows`
- Windows MSIX: `dart run msix:create` builds `build/windows/x64/runner/Release/*.msix` (runs `flutter build windows` first). Config lives in the `msix_config` block of `pubspec.yaml`; `--store` targets the Microsoft Store. Keep `msix_version` (a.b.c.d) in sync with `version:`.
- Version bumps: use the `sync-version` skill (`.claude/skills/sync-version/`) — the version is hardcoded in four places and they drift otherwise.

**CI** (`.github/workflows/pr-check.yml`) runs format, analyze and test on every PR to `main`. Run all three before pushing — an unformatted file or a lint *info* fails the build.

## Conventions

- The checkable conventions are lints in `analysis_options.yaml`: `prefer_relative_imports`, `directives_ordering`, `prefer_single_quotes`, `always_declare_return_types`, `use_super_parameters`, `unawaited_futures`. A future deliberately not awaited is wrapped in `unawaited(...)`.
- A new library goes in its feature's folder, and its test goes at the mirrored path under `test/` in the same commit (see [Source layout](#source-layout)). New top-level directories under `lib/` need a reason.
- All path manipulation goes through the `path` package — never string concatenation.
- Any code that writes to disk must go through `applyOrganizeAction` (or `MetadataWriter` for scrape output, `executeTransfer` for a copy/cut/paste) or justify why not, and must validate with `PathSafety.isWithin(..., context:)`.
- Every user-facing string uses `AppLocalizations.of(context)!.<key>` and is added to **both** `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` (codegen via `l10n.yaml` + `flutter: generate: true`). Never hand-edit the generated `lib/l10n/app_localizations*.dart`.
- New keyboard shortcuts go in `lib/shortcuts/app_shortcuts.dart` — no bare `SingleActivator` in a widget. That list also feeds `HomeScreen`'s `CallbackShortcuts` and renders Settings → Shortcuts, so a shortcut is one entry. Activators are platform-aware (`meta:` on macOS, `control:` elsewhere).
- Failures are reported via `ScaffoldMessenger`; batch operations report counts, not just the first error.
- **No literal colours, radii, control heights, font sizes or durations in a widget.** Read `context.tokens` / `AppSpacing` / `AppRadii` / `AppSizes` / `AppMotion` / `AppTypeScale`. A one-off value (the 680x340 drop zone, the 46x5 confidence bar) names the spec section it came from in a comment. The spec is `docs/spec/ui-redesign/`.
- Build from the `lib/widgets/ui/` primitives rather than styling a bare Material control. Dialogs use `GlassAlertDialog` (or `GlassDialogSurface` inside a transparent `Dialog`) with `DialogActionBar`; context menus use `showGlassMenu` with `glassMenuItem`/`glassMenuHeader`. Never a bare `AlertDialog` or `showMenu`.
- Never write a second `BackdropFilter` — use `GlassSurface`.
- A new full-page `Navigator.push` surface must include `SecondaryTitleBar` and go through `AppPageRoute`.
- Design-spec features the app cannot yet do ship as the design's own placeholder (drawn, disabled, labelled — `SettingsPlaceholder` + `SettingsSoonTag` in settings) and go in `docs/spec/ui-redesign/backlog.md` — not omitted, not faked.
- No `freezed` / `json_serializable` / `build_runner` — JSON is hand-rolled in the owning service.

## Architecture

### Source layout

`lib/` is organized by **feature, not by layer**. Every UI area is a folder under `lib/widgets/` (`ai`, `dialogs`, `file_browser`, `glass`, `home`, `onboarding`, `scrape`, `settings`, `shell`, `sidebar`, `tasks`, `ui`), and the screen that owns an area lives in it — `HomeScreen` in `lib/widgets/home/`, `SettingsScreen` beside its section files. There is no `lib/screens/`.

`lib/services/` splits the same way: a service belonging to one pipeline lives in that pipeline's folder — `ai/`, `organize/`, `scrape/`, `metadata/`, `agent/`, `thumbnails/`, `transfer/`. Only app-wide services stay loose at the top (`settings_service`, `file_browser_service`, `file_label_service`, `font_service`, `history_service`, `task_service`), with the two pure helpers every pipeline uses, `path_safety` and `gpu_info`.

**`test/` mirrors `lib/` path for path** (`test/main_test.dart` boots `lib/main.dart`), so "is this covered?" is answered by looking. A moved library moves its test in the same commit. `test/helpers/` (in-memory FS, scripted AI provider) and `test/fixtures/` are the only exceptions.

Imports inside `lib/` are **relative**; tests use `package:` URIs.

### App shell

`lib/main.dart` initializes services, then runs `MyApp` → `HomeScreen` (or `OnboardingScreen` until `settings.onboardingSeen`). **No router**: full-page surfaces are `Navigator.push`, everything else is a dialog. `HomeScreen` is `AppSidebar` (244px) | `MediaTable` | `AiAssistantPanel` (352px) over a 28px status bar, with sections Files, Library (placeholder), Tasks.

- **Init order matters.** `AiProfilesService.init()` runs *before* `SettingsService.init()` (it migrates AI keys out of the legacy `config.json`, which `SettingsService` would otherwise rewrite without them). `FontService.init()` + `loadIfDownloaded()` complete before `runApp`, or the first frame flashes the system font.
- **The OS title bar is hidden**; one 48px bar carries brand, tabs, search, actions and — on Windows/Linux — our own 46x48 caption buttons. Every full-page route therefore needs `SecondaryTitleBar` or the window loses its drag region and buttons. `AppShell` deliberately does not clip (the OS rounds the frameless window).
- **Window state is read once**, through `WindowStateScope` ([window_state.dart](lib/widgets/shell/window_state.dart)) — never attach a `WindowListener` per widget.
- **No app content in the top-right 138px** on Windows (reserved for the Snap Layouts hit area, which currently does not work — backlog B15).
- **`MediaTable` subscribes narrowly on purpose**: one `context.select` per value, per-row selection watches, column-drag widths local in a `ValueNotifier` until release (cancel commits too). `SettingsService.columnWeights` caches its map so `select`'s `==` holds. Don't turn these into `watch`.
- Minimum window size is 1024x700 (`window_manager` in `main()`); below it the fixed-width panes overflow.

Title bar, Snap Layouts, macOS traffic lights, GPU adapter and the thumbnail worker: [window-and-native.md](docs/architecture/window-and-native.md).

### Services

Ten `ChangeNotifier`s are registered in `lib/main.dart`:

| Service | Owns |
|---|---|
| [settings_service.dart](lib/services/settings_service.dart) | Theme, locale, accent, glass intensity, font choice, favorites, recents (cap 8), onboarding flag → `config.json`; search sites → `sites.json` |
| [ai_profiles_service.dart](lib/services/ai/ai_profiles_service.dart) | AI channels (key + host), their routes (protocols) and models, and which model each task runs on → `ai_profiles.json` |
| [ai_service.dart](lib/services/ai/ai_service.dart) | Live `AiConfig`, connection status, **the single current `OrganizePlan`**, usage stats |
| [file_browser_service.dart](lib/services/file_browser_service.dart) | Current directory, file list, focus + multi-selection, sort state, `FileSystemEvent` watcher |
| [task_service.dart](lib/services/task_service.dart) | The Tasks-tab list of running/finished analyze, apply and scrape-commit tasks |
| [history_service.dart](lib/services/history_service.dart) | Undo manifests under `undo/op-*.json`, 7-day retention |
| [font_service.dart](lib/services/font_service.dart) | Optional downloadable CJK UI fonts (HarmonyOS Sans SC, MiSans) |
| [recipe_store.dart](lib/services/scrape/recipe_store.dart) | Learned / user-edited scrape recipes → `scrapers.json`, plus per-recipe health counters |
| [scrape_service.dart](lib/services/scrape/scrape_service.dart) | One scrape at a time: fetch → extract → merge plan → commit |
| [file_clipboard.dart](lib/services/transfer/file_clipboard.dart) | The file browser's copy/cut clipboard: absolute paths + mode, in memory only |

[apply_controller.dart](lib/services/organize/apply_controller.dart) and [transfer_controller.dart](lib/services/transfer/transfer_controller.dart) are `ChangeNotifier`s but **not** registered — one per apply / per paste, owned by its `OrganizerTask`. Everything else is plain: the `AiProvider`s, `AiHttp`, `AiCancelToken`, the agent runtime and its agents, `path_safety`, `organize_service` (one top-level function), `gpu_info`, and all models.

`AiService.updateConfig` is called from a widget `build()`, so it early-returns when unchanged and defers `notifyListeners` to a post-frame callback. Breaking either causes "setState() during build".

### The organize pipeline

Read [organize-pipeline.md](docs/architecture/organize-pipeline.md) before touching `lib/services/ai/`, `lib/services/organize/`, `lib/services/agent/` or `lib/widgets/ai/`.

Flow: `_organize()` in [home_screen.dart](lib/widgets/home/home_screen.dart) (empty selection = whole folder) → title hint dialog → `TaskService.startAnalyze` (fires `AiService.analyzeFolder` unawaited) → [organize_agent.dart](lib/services/organize/organize_agent.dart) → `OrganizeState.buildPlan` → `OrganizePreviewDialog` → `ApplyController` → `applyOrganizeAction` per action → undo manifest.

- **The preview is the only dry run and the only gate.** Cancel means nothing touched disk. Apply **skips `needsReview` actions** (confidence `< 0.6`, unsure/undecided groups, unplaceable files, and both sides of a target collision).
- **The model never writes or names a path.** It refers to groups by id and files by number; `source` comes from the scan and `target` from `JellyfinNaming`. Code does everything with a right answer (`FilenameParser`, `Grouping`, `JellyfinNaming`); the model only decides what a group *is*. Keep new organize tools to that contract. `identify_from_frames` (opt-in, frames to a model allowed image input) only reports on-screen text, and a group decided after it is always flagged for review.
- **Only one plan exists app-wide.** A second `analyzeFolder` nulls the current one (last writer wins). The scan is capped at 400 files, dotfiles skipped; large folders go in batches of ≤12 groups, each a fresh session.
- **`OrganizeAction.target` is mutable on purpose** so the preview can correct it in memory; every disk write stays behind `ApplyController`.
- **`backup` copies nothing** in organize — it only gates writing the undo manifest. (In scraping it really copies.)
- **Decisions are remembered by fingerprint** (path + size + mtime, [organize_workspace.dart](lib/services/organize/organize_workspace.dart)); only an *applied* preview's edits are remembered. A changed fingerprint is a miss, an unreadable cache is empty.
- **Every AI task needs a tool-calling model; there is no single-shot fallback.** Tool support is probed and stored per provider | endpoint | model, on the model's route parameters. One adapter per protocol family (Chat Completions, Gemini, Anthropic, Responses); vendor differences (paths, reasoning switches) live in `PlatformProfiles` as data, never as vendor branches. A turn that must go back verbatim (signatures, encrypted reasoning) is a `ProviderTurn`, returned only to the protocol and model that wrote it; Chat Completions' reasoning, Volcengine's `encrypted_content` included, rides on `ReasoningPassback` and goes back on tool-call turns only — see [Channels, routes and models](docs/architecture/organize-pipeline.md#channels-routes-and-models). The probe has **three** outcomes — a transport failure, an account or rate-limit status, a server error or any other refusal is `inconclusive` and is never recorded; only a 400/422 naming tools, or prose twice, is `unsupported`.
- **Cancellation closes the token's own `http.Client`**, so cancellable requests must never use the shared `AiHttp.client`.
- **Never interpolate a transport exception into UI or logs** (`'Network error: $e'`): `ClientException` carries the URL, and Google's URL carries the API key. Use `AiHttp.describeTransportError`.
- Timeouts are on *silence*, not duration, and a timed-out generation — a client timeout, 408 or 504 — is never resent by the transport (the server may still be running it); an organize batch that throws is still rerun once, as a fresh session. Per-server memories (JSON mode, refused fields, how reasoning was turned off) are keyed by provider | base URL | model | key hash, persisted in `ai_learned.json` (30 days), and forgotten by the connection test, which is how a user makes the app find out again.
- `/v1` is appended only to a bare origin; a URL with a path is used as typed, except that a pasted Messages `…/messages` or Gemini `…/models…` endpoint is cut back to its root. A 404 or 405 names the URL it went to (never its query string); no other error does. A blank key on an OpenAI-compatible profile sends no `Authorization` header.
- `AiConfig.contextWindow` is a client-side budget, not a server setting; `AgentRuntime.trimHistory` shrinks old tool results to stay inside it and **never removes a message**.
- Sampling comes from ordered per-family presets ([sampling_presets.dart](lib/services/ai/sampling_presets.dart)): more specific families first, every row cites its model card, no invented presets, values always sent explicitly. Reasoning is off by default and judged by whether the reply still reasoned.
- [agent_runtime.dart](lib/services/agent/agent_runtime.dart) is the one tool loop: every tool call gets a reply (even on cancel), a bad call is a `ToolError` phrased as the next step, three failed rounds end the run as `erratic` (unless the replies were cut off at the output limit — that is `truncated`), nudges are retracted after sending, and nothing relies on a forced `tool_choice`.

### Filesystem writes

**`applyOrganizeAction` in [organize_service.dart](lib/services/organize/organize_service.dart) is the single chokepoint for moves.** It validates source and target with `PathSafety.isWithin(baseDir, ..., context:)` (so an in-memory POSIX FS isn't parsed with Windows rules), refuses to clobber an existing target except for case-only renames, falls back to copy+delete across volumes (deleting the copy if the source delete fails), and records `action.status`/`error` without aborting the batch. It takes a `FileSystem` (package `file`) so tests use an in-memory FS.

`MetadataWriter` is the second chokepoint, for scrape output — same obligations, but it writes new content and may overwrite.

`executeTransfer` in [file_transfer.dart](lib/services/transfer/file_transfer.dart) is the third, for the file browser's copy/cut/paste — see [File browser transfers](#file-browser-transfers).

### File browser transfers

Read [file-browser.md](docs/architecture/file-browser.md) before touching `lib/services/transfer/` or `lib/widgets/file_browser/file_transfer_flow.dart`.

Flow: copy/cut (context menu, ⌘C/⌘X, whole selection or the focused row) → `FileClipboard` → paste (⌘V, a folder row's menu, or the table footer's clipboard chip) → `planTransfer` → conflict dialog when a name is taken → `TransferController` under `TaskService.startTransfer` → `executeTransfer` per item → undo manifest.

- **The clipboard is app-internal** (paths in memory, not the OS clipboard — backlog B25). A cut only dims its rows; nothing moves until the paste, and Esc with nothing selected calls a cut off.
- **A paste never overwrites.** A taken name is either skipped or numbered `name (2).ext`; the policy is chosen once per paste and applied at run time, so a file that appeared after planning is still safe.
- **Refused before running**: a missing or unreadable source, a symbolic link or a folder holding one, a folder pasted into itself or a child of itself, a move into the folder the item already sits in. Every refusal is reported, even when the rest goes ahead.
- **Directories**: a move tries one `rename` and records each file inside for undo; across volumes it copies, then removes the source **file by file** once the whole tree copied — a source that cannot be fully removed keeps the copy and fails the item, never the reverse. A stop or failure mid-copy removes the partial copy. Undo does not recreate empty subfolders at the source, and an empty folder's move records nothing (`no undo`).
- **Undo** is a `HistoryKind.fileTransfer` manifest — moves in `moves`, copies in `created` — whose `baseDir` is the deepest folder holding every path. Two Windows drives share none, so that paste records nothing and the summary says `no undo`.

### Undo

[history_service.dart](lib/services/history_service.dart) writes `<appSupport>/undo/op-<millis>.json`. A manifest holds `moves` (reversed in reverse order; an already-present source counts as success), `created` (deleted on undo) and `restored` (copied back from `<appSupport>/undo/blobs/<opId>/`).

- Every path is re-checked with `PathSafety` against a tampered manifest: moves and `created` against `baseDir`, a `restored` **source against the undo directory**.
- Full success deletes manifest and blobs; **partial success rewrites the manifest with only the unrecovered work**.
- `refresh()` pruning at `retentionDays = 7` (manifests, and blob dirs by newest file) *is* the UI's 7-day promise. Undo does not remove directories the operation created.
- All path work goes through `_fs.path` with `context:` passed to `PathSafety`.
- `record` is the organize manifest, `recordScrape` the scrape one and `recordTransfer` the copy/cut/paste one; a transfer with nothing moved or created writes no manifest.

### Metadata scraping

A second pipeline, parallel to organize and sharing only `AiProvider`: product-page URL → extract → reviewable diff against the NFO on disk → write. Read [metadata-scraping.md](docs/architecture/metadata-scraping.md) before touching `lib/services/scrape/`, `lib/services/metadata/` or `lib/widgets/scrape/`; the original design is in [docs/spec/scrape-module-spec.md](docs/spec/scrape-module-spec.md).

- **Not routed through `OrganizePlan`** — a stray Organize click would discard uncommitted metadata.
- Extraction ladder, cheapest first: structured data (always checked with `isSiteWideTemplate`) → declarative `ScrapeRecipe` → LLM-written recipe (only when no recipe exists) → user-pasted HTML. "Ask the LLM directly" ([direct_extractor.dart](lib/services/scrape/direct_extractor.dart)) is an override, not a tier; a folder refresh never uses it.
- **A learned recipe is never saved automatically** — only the preview's confirmation puts it in `RecipeStore`, because a recipe that grabs a truncated synopsis looks healthy. Everything LLM-sourced is `FieldOrigin.llm` and flagged; an LLM value never overwrites an existing one.
- The model **chooses images by number** from `list_images`; it never supplies a URL.
- [page_fetcher.dart](lib/services/scrape/page_fetcher.dart) is the only code that talks to a scraped site. It follows redirects itself, owns encoding, cookies (recipe < own session < imported, all memory-only), `Referer` (site root by default) and a per-host request interval. A recipe's `sessionUrl` must be on the same host.
- **Only the commit task writes.** `NfoWriter` replaces only `managedElements`; `NfoMerge` defaults to fill blanks, keep conflicts. The scrape `backup` checkbox gates both real copies and the manifest.
- **Jellyfin identifies artwork by file name**: `ImageRole.stem` is the file name, one role per image type, single-slot roles are exclusive, unmarked images keep the server's name. `ImageNaming.plan` takes the extension from magic bytes and sanitizes the stem.
- NFO names follow Jellyfin: `movie.nfo`, or `<video>.nfo` in a mixed folder (`MetadataWriter.nfoNameFor`); `tvshow.nfo` for series. A refresh keeps the existing root element.
- Folder refresh re-fetches only pages recorded in the NFO's `<!-- scraped from … -->` comment, applies default merge plans, is serial, and writes one manifest.
- `test/fixtures/giga_product_7743.html` is real markup pinning duplicated ids and folded/expanded synopsis copies.

Not done yet: the Library section, recipe import/export, feeding scraped title/year into organize. The full list is `docs/spec/ui-redesign/backlog.md`.

### Persistence

Everything lives in the `path_provider` application-support directory, as hand-rolled JSON in the owning service:

- `config.json` — settings (debounced 250ms, flushed on dispose). A legacy `performance_mode: true` migrates to `glass_intensity: 0` and the key is dropped. `baked_glass` defaults to true.
- `ai_profiles.json` — AI channels, routes, models, task assignments and keys (`"v": 2`), kept separate so a slider drag never rewrites keys. A file without `channels` is read as flat profiles, byte-identically; a flat `ai_services` mirror is still written for older builds
- `ai_learned.json` — what each route refused or ignored ([learned_behaviour.dart](lib/services/ai/learned_behaviour.dart)); holds a key hash, never a key
- `logs/api-<date>.jsonl` — the opt-in AI request log ([api_log.dart](lib/services/ai/api_log.dart), Settings → Privacy, 7 days): every body sent, no headers, no query strings, images replaced by their length and long strings cut to 200 characters
- `sites.json` — custom search sites
- `scrapers.json` — learned / user-edited scrape recipes (built-ins live in code)
- `undo/op-*.json`, `undo/blobs/` — undo manifests and backup copies
- `thumbnails/*.jpg` — thumbnail cache (64 MB, keyed by `sha1(path|mtime|size)`)
- `agent/organize/<folder hash>.json` — remembered decisions (7 days, newest 20 folders)
- `agent/overrides.json` — targets corrected in applied previews (dropped after 180 days unused)
- `fonts/<id>/*.ttf` — downloaded UI fonts

### Theming

Read [rendering-and-theming.md](docs/architecture/rendering-and-theming.md) before touching `lib/theme/`, `lib/widgets/ui/` or `lib/widgets/settings/`. Rendering changes are measured, not guessed: a maximized 4K frame on an iGPU went 80.4 ms → 1.74 ms, and most of what was assumed along the way was wrong.

- **[design_tokens.dart](lib/theme/design_tokens.dart) is the only source of paintable values.** `AppSpacing`/`AppRadii`/`AppSizes`/`AppMotion`/`AppTypeScale` are `static const`; colours, gradients, shadows and blur are the `AppTokens` extension (`context.tokens`); `AppPalette` holds the theme-independent semantic hues and vendor marks. There are exactly eight type sizes.
- **Never animate a colour to/from `Colors.transparent`** (transparent *black* → grey flash). Use the target colour at `withValues(alpha: 0)`.
- A ghost control's hover is `AppTokens.hoverOverlay`, not `controlFill` (a white wash that vanishes over a white card).
- Nothing derived from the user-replaceable accent is hardcoded; `AppTokens.badgeText` flips to ink above 0.72 luminance.
- **Fonts:** `ThemeData.fontFamily` stays the platform Latin UI face (`AppTypeScale.latinUi`); the picked CJK font goes first in `fontFamilyFallback`. Never write a bare `DefaultTextStyle(style:)` — use `DefaultTextStyle.merge`. Mono text uses `context.tokens.monoSmall`/`monoTiny`/`monoBody` (or `context.tokens.monoFallback`), never a bare `fontFamily`.
- **Control metrics live in `AppTheme`**, not widgets: `InputDecoration` carries only content; an explicit size is a deliberate compact variant that opts out of the theme borders.
- **`GlassSurface` ([glass_surface.dart](lib/widgets/ui/glass_surface.dart)) is the only `BackdropFilter`.** It drops the filter under an opaque fill; skips the widget entirely at intensity 0; uses `BackdropFilter.grouped` under `AppShell`'s `BackdropGroup` (pushed routes never find it, and must not); draws the pre-baked blur crop when `BakedBackdropScope` provides one; always clips; and doesn't blur under an opaque route (`GlassCoverScope`).
- **The baked path assumes nothing dynamic sits behind a glass tile at the same level.** Don't put live content there. `test/widgets/ui/baked_glass_test.dart` and `backdrop_group_test.dart` pin this.
- **`AppBackdrop` ([app_backdrop.dart](lib/widgets/ui/app_backdrop.dart)) bakes the window gradients into an image** (window aspect, quantised size, 120ms debounce, disposed on replace, blur with `TileMode.clamp`). Never draw a second full-window gradient live — that alone cost ~21 ms. `RepaintBoundary` cannot substitute.
- **The bake's downscale is counted in *device* pixels** — 2 per texel for the sharp image, 4 for the blurred copies — while the re-bake quantum is counted in *logical* pixels, before the split, so the two layers stay locked to each other. A gradient is rasterized *with dither*, and the stretch magnifies that noise: sizing off logical pixels made it 8 device px per texel on a Retina display and the backdrop read as a dishcloth. Blurring the dither away is not the fix — it trades the grain for contour banding. `test/widgets/ui/backdrop_bake_resolution_test.dart` pins the sizing.
- **Glass intensity 0 is the only low-GPU mode** (`AppTokens.reduceEffects`): opaque pre-mixed fills, stronger hairlines, no large shadows. There is no separate performance toggle.
- The app does **not** pin a GPU adapter — `DartProject::set_gpu_preference` breaks `media_kit` textures.
- `AppTheme.light`/`.dark` memoize one `ThemeData` per brightness; don't replace with a map keyed by inputs.
- **Motion**: 80ms hover, 120/100ms overlays, 180ms panels, 240ms linear progress, no section transition; only opacity, fill and ≤4px movement — no scaling, no elastic curves. `AppMotion.respecting(context, ...)` honours reduced motion.

**Settings screen:** a 200px nav plus one pane; each section is a library under `lib/widgets/settings/`, built only from the blocks in [settings_controls.dart](lib/widgets/settings/settings_controls.dart).

- A multi-row settings page is one `SettingsColumns(equalHeight: true)` **per grid row** with an `AppSpacing.lg` gap — never one `SettingsColumns` holding two `Column`s. `equalHeight` is `IntrinsicHeight`, so children must answer intrinsic height (no `LayoutBuilder`).
- Group labels and footnotes go **inside** the card (`header` / `footer`), never above or below it.
- Undo backups have **no Clear button** (they back unexpired undo records).
- The accent picker previews live, so cancel is a real rollback, and only Apply records a recent (`setAccentColor(remember:)`).
- Context-window slider math is the pure [context_window_scale.dart](lib/widgets/settings/context_window_scale.dart); typed input aligns **down** to 1k.

### media_kit

Used for exactly one thing: playing a local video in [preview_dialog.dart](lib/widgets/dialogs/preview_dialog.dart), plus `MediaKit.ensureInitialized()` in `main()`. No metadata extraction or duration probing. Migrating to `video_player` was evaluated and rejected (no official Windows/Linux support; Media Foundation can't play what the host lacks codecs for) — don't revisit without new information.

### Thumbnails

[thumbnail_service.dart](lib/services/thumbnails/thumbnail_service.dart): in-memory LRU + JPEG disk cache. **Windows bypasses `fc_native_video_thumbnail`** (it blocks the platform thread) and uses [windows_thumbnailer.dart](lib/services/thumbnails/windows_thumbnailer.dart) → the runner's `jellyfin/thumbnail` channel ([thumbnail_channel.cpp](windows/runner/thumbnail_channel.cpp)); a `MissingPluginException` latches back to the plugin. Every failure degrades to the type icon — thumbnails are never load-bearing. The C++ threading rules are in [window-and-native.md](docs/architecture/window-and-native.md#thumbnails).

### Legacy that is still live

- [rename_service.dart](lib/services/organize/rename_service.dart) is down to `buildName` and `baseNameForTarget`, used by [edit_action_dialog.dart](lib/widgets/ai/edit_action_dialog.dart). `baseNameForTarget` must walk *past* `Season NN` / `Specials` to the series folder, or TV renames produce `Season 01.S01E01.mkv`.
- `lib/widgets/dialogs/{tv_show,part,subtitle}_dialog.dart` are **not dead** — `EditActionDialog` builds them from the organize preview. Do not delete them.

## Platform-specific notes

- **macOS entitlements are split**: `DebugProfile.entitlements` (JIT, network server for `flutter run`) and `Release.entitlements` (stricter). A new capability goes in **both**.
- **macOS still uses CocoaPods** because `media_kit_video` 2.0.1 and `media_kit_libs_macos_video` 1.1.4 ship no `Package.swift`. `macos/Podfile` and `Podfile.lock` are **required — do not delete**, and keep the `#include? ".../Pods-Runner.*.xcconfig"` lines in `macos/Flutter/Flutter-{Debug,Release}.xcconfig` *above* the `ephemeral/Flutter-Generated.xcconfig` include. The "plugins do not support Swift Package Manager" warning is expected. Drop CocoaPods once [media-kit#1412](https://github.com/media-kit/media-kit/pull/1412) is published (track [#1399](https://github.com/media-kit/media-kit/issues/1399), [#1435](https://github.com/media-kit/media-kit/pull/1435)).
- **`intl` is pinned to `0.20.2`**, not a caret range — `flutter_localizations` pins it exactly, and `^0.20.3` fails version solving.
- **Google GenAI sends the API key in the `x-goog-api-key` header**, never as `?key=` (a query string lands in every proxy's access log).
- **Linux** needs system FFmpeg + libjpeg for thumbnails and libmpv for playback; without them both degrade to icons.
- **Identity:** org `joycai.cn`; product name `Jellyfin Media Management Tool`, set in `macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_NAME`, which names the `.app`; `Info.plist` derives its bundle names from it), `windows/runner/Runner.rc` + `main.cpp`, `linux/runner/my_application.cc`, `scripts/inno_setup.iss` (`MyAppName`), the release workflow's DMG paths, `appBrand` / `onboardingWelcomeTitle` in both ARB files, and the window title in `MainFlutterWindow.swift`. The Windows/Linux **binary** stays `jellyfin_media_management_tool` (`BINARY_NAME` is also the CMake target, which cannot contain spaces).
