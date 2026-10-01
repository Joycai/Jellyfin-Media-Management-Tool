# AGENTS.md

This file provides repository instructions for Codex and other coding agents.

Read the relevant sections of [subsystem invariants](docs/architecture/agent-invariants.md) before changing a subsystem. This file holds the shared workflow and conventions; that reference preserves the detailed rules. The reasons, measurements and history behind them are in [`docs/architecture/`](docs/architecture/) — read the matching file before changing a subsystem, and update both in the same commit when a rule changes.

## Project overview

- Flutter **desktop** app for Windows/macOS/Linux. There are no `android/`, `ios/` or `web/` directories — those targets are not supported, and `flutter create` scaffolding for them should not be re-added.
- A local file-management tool that organizes media libraries to match Jellyfin's [naming conventions](https://jellyfin.org/docs/general/server/media/naming/). It does **not** talk to Jellyfin servers — there is no API client or auth; everything is filesystem operations.
- The primary workflow is **AI-driven**: point it at a folder, an LLM proposes a move/rename plan, the user reviews and edits the plan in a preview dialog, and only then does anything touch disk. Every applied batch writes an undo manifest.
- Dart SDK `^3.10.4`. Current app version: `1.3.4+8`.

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
- Version bumps: use the `sync-version` skill (`.agents/skills/sync-version/`) — the version is hardcoded in four places and they drift otherwise. `scripts/check_version_sync.sh` asserts they agree; CI runs it.
- The Flutter version CI builds with is pinned once, in `.fvmrc` (both workflows read it via `flutter-version-file`). `fvm use` picks up the same file locally. Keep the local SDK on that version: a newer `dart format` splits code differently, and `flutter pub get --enforce-lockfile` in CI refuses a lock file resolved under a different SDK.

**CI** (`.github/workflows/pr-check.yml`) runs format, analyze and test on every PR to `main`, after checking that `pubspec.lock` resolves as committed, that the generated `lib/l10n/*.dart` match the ARB files, and that the version copies agree. Run format, analyze and test before pushing — an unformatted file or a lint *info* fails the build. `build.yml` compiles the three desktop runners (`flutter build <os> --release`) on every push to `main`, and on a PR only when `windows/`, `macos/`, `linux/`, `pubspec.*` or `.fvmrc` changed — `flutter test` never compiles native code, so that is the only pre-release check of it. `release.yml` (manual) reuses `pr-check.yml` as a gate, builds the DMG, the Windows installer + portable ZIP and a Linux tarball, and takes the release body from the version's `CHANGELOG.md` section.

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

## Source layout

`lib/` is organized by **feature, not by layer**. Every UI area is a folder under `lib/widgets/` (`ai`, `dialogs`, `file_browser`, `glass`, `home`, `onboarding`, `scrape`, `settings`, `shell`, `sidebar`, `tasks`, `ui`), and the screen that owns an area lives in it — `HomeScreen` in `lib/widgets/home/`, `SettingsScreen` beside its section files. There is no `lib/screens/`.

`lib/services/` splits the same way: a service belonging to one pipeline lives in that pipeline's folder — `ai/`, `organize/`, `scrape/`, `metadata/`, `agent/`, `thumbnails/`, `transfer/`. Only app-wide services stay loose at the top (`settings_service`, `file_browser_service`, `file_label_service`, `font_service`, `history_service`, `task_service`), with the two pure helpers every pipeline uses, `path_safety` and `gpu_info`.

**`test/` mirrors `lib/` path for path** (`test/main_test.dart` boots `lib/main.dart`), so "is this covered?" is answered by looking. A moved library moves its test in the same commit. `test/helpers/` (in-memory FS, scripted AI provider) and `test/fixtures/` are the only exceptions.

Imports inside `lib/` are **relative**; tests use `package:` URIs.

## Subsystem guidance

Read the matching sections of [agent-invariants.md](docs/architecture/agent-invariants.md) and the architecture note before editing these areas:

| Area | Architecture note |
|---|---|
| AI providers, agent runtime, organize services and preview | [organize-pipeline.md](docs/architecture/organize-pipeline.md) |
| Scraping, metadata, NFO and artwork writes | [metadata-scraping.md](docs/architecture/metadata-scraping.md) |
| Copy/cut/paste, clipboard and transfer undo | [file-browser.md](docs/architecture/file-browser.md) |
| Theme, glass, fonts and settings controls | [rendering-and-theming.md](docs/architecture/rendering-and-theming.md) |
| Desktop runners, title bars and thumbnails | [window-and-native.md](docs/architecture/window-and-native.md) |
| App shell, service initialization, persistence and legacy code | [agent-invariants.md](docs/architecture/agent-invariants.md) |

Keep the invariants and the matching architecture note current in the same commit as a behavior change.

## Agent workflow

- Use `codex/` for new branches. This tooling migration does not change the app version; normally bump once at release time, using `sync-version` when a version change is requested.
- Repository conventions govern generic Dart/Flutter skill examples. Keep the existing feature-based layout and hand-written JSON; do not introduce `freezed`, `build_runner`, generated mocks, a router, or a new layered architecture because a generic skill recommends them. Use the existing test helpers and injected dependencies.
- The repository skills live in `.agents/skills/`. Preserve `skills-lock.json` for the upstream Flutter skill provenance; `sync-version` is maintained locally.
- The branch-version reminder is configured in `.codex/hooks.json`. Review and trust its definition with `/hooks` in Codex CLI before relying on automatic reminders. The hook only emits context and never changes a version. Its absence does not relax the version-sync CI check.
- Keep local tasks and worktrees out of commits. Existing `.claude/worktrees/` checkouts are preserved local Git state; do not delete or move them during configuration cleanup.
