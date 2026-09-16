# Contributing

Thanks for looking. This file is the short version: what to install, what the
build gates are, and the handful of conventions that are load-bearing rather
than taste. The long version — every invariant worth knowing before you change
something — is [CLAUDE.md](CLAUDE.md), and it is kept current.

## Getting set up

You need the Flutter SDK (Dart `^3.10.4`). CI builds on **Flutter 3.44.2**, so
that is the version to match if something only breaks for you.

```bash
git clone https://github.com/Joycai/Jellyfin-Media-Management-Tool.git
cd Jellyfin-Media-Management-Tool
flutter pub get
flutter run -d macos     # or windows / linux
```

This is a **desktop-only** app. There is no `android/`, `ios/` or `web/`
directory and they are not supported targets — please don't re-add the
`flutter create` scaffolding for them.

Platform notes:

- **Linux** needs libmpv for the video preview (`apt install libmpv-dev mpv`)
  and system FFmpeg + libjpeg for thumbnails. Without them previews and
  thumbnails fall back to icons; nothing else breaks.
- **Windows and macOS** bundle libmpv already.
- **macOS** still resolves `media_kit` through CocoaPods. `macos/Podfile` and
  `macos/Podfile.lock` are checked in and required. The build-time warning
  about plugins not supporting Swift Package Manager is expected.

## The three gates

CI runs exactly these three on every pull request, and a lint **info** fails the
build, not just an error. Run all three before pushing:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

`flutter test test/services/organize/organize_service_test.dart` runs one file.
`flutter gen-l10n` regenerates localization, and `flutter run` does it for you.

`analysis_options.yaml` enables the handful of lints that encode conventions
this repo already followed — relative imports inside `lib/`, directive ordering,
single quotes, declared return types, and `unawaited()` on a future the code
deliberately drops. `dart fix --apply` resolves most of what they flag.

## Where code goes

`lib/` is organized by **feature, not by layer**, and `test/` mirrors it path
for path. The rule and its edges are written out in
[CLAUDE.md § Source layout](CLAUDE.md#source-layout); the summary is:

| Path | Holds |
|---|---|
| `lib/models/` | Plain data types, hand-rolled JSON |
| `lib/services/<pipeline>/` | Services belonging to one pipeline — `ai/`, `organize/`, `scrape/`, `metadata/`, `agent/`, `thumbnails/` |
| `lib/services/*.dart` | Only app-wide services and the pure helpers `path_safety` / `gpu_info` |
| `lib/widgets/<area>/` | One folder per UI area, including the screen that owns it |
| `lib/widgets/ui/`, `lib/widgets/glass/` | The design-system primitives everything else is built from |
| `lib/theme/` | `design_tokens.dart` — the only place a colour, radius, size, duration or type step is written down |
| `lib/l10n/` | ARB files; the generated `app_localizations*.dart` are **not** hand-edited |
| `docs/spec/` | The design and module specs the code is written against |

A new library goes in its feature's folder and its test goes at the mirrored
path in the same commit. A new top-level directory under `lib/` needs a reason.

## Conventions that are not negotiable

These each exist because the alternative broke something. CLAUDE.md says which.

- **Every disk write** goes through `applyOrganizeAction` or `MetadataWriter`,
  and validates with `PathSafety.isWithin` — passing `context:` so an injected
  in-memory POSIX filesystem isn't parsed with Windows rules.
- **All path manipulation** goes through the `path` package. Never string
  concatenation: it is wrong on the other OS.
- **Every user-facing string** is `AppLocalizations.of(context)!.<key>`, added
  to **both** `app_en.arb` and `app_zh.arb`.
- **No literal colours, radii, control heights, font sizes or durations in a
  widget.** Read `context.tokens` / `AppSpacing` / `AppRadii` / `AppSizes` /
  `AppMotion` / `AppTypeScale`. A deliberate one-off names the spec section it
  came from, in a comment.
- **Build from `lib/widgets/ui/`**, not from bare Material controls. Dialogs use
  `GlassAlertDialog` / `GlassDialogSurface`; menus use `showGlassMenu`. Never a
  bare `AlertDialog` or `showMenu`.
- **Never write a second `BackdropFilter`** — `GlassSurface` is the only one.
- **New keyboard shortcuts** go in `lib/shortcuts/app_shortcuts.dart`, which the
  Settings → Shortcuts table renders from. One entry, not three edits.
- **Failures surface through `ScaffoldMessenger`**, and a batch reports counts
  rather than only its first error.
- **No `freezed` / `json_serializable` / `build_runner`.** JSON is hand-rolled
  in the owning service.

Designed-but-unbuilt UI ships as the design's own placeholder — drawn, disabled
and labelled — and gets a line in
[`docs/spec/ui-redesign/backlog.md`](docs/spec/ui-redesign/backlog.md). Dropping
such a block reads as "not planned", and faking it is worse.

## Tests

`test/` mirrors `lib/`, with `test/helpers/` and `test/fixtures/` as the two
shared exceptions. `test/helpers/fs.dart` gives you an in-memory filesystem —
anything that writes to disk is tested against it rather than against `/tmp` —
and `test/helpers/ai.dart` gives you a scripted model, so agent and provider
behaviour is pinned without a network call.

Write the test for the behaviour that broke, not for the line that changed. The
existing tests are documentation about *why* — several of them carry a header
comment explaining what the failure looked like — and that is worth keeping up.

## Commits and pull requests

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/)
with an optional scope, lowercase, describing what the change does:

```
feat(settings): the model-parameters page and its context slider
fix(shell): full-page routes get their own 48px bar, or the window loses its controls
perf: bake the window backdrop, share one backdrop snapshot
docs: record that Snap Layouts is verified broken, not merely unverified
```

`feat`, `fix`, `perf`, `refactor`, `style`, `docs`, `test`, `chore`, `ci`.

Branch off `main`, keep a pull request to one subject, and say in the
description what you verified — "838 tests pass" and "measured at 4K maximized"
are the useful kind. If your change invalidates something CLAUDE.md asserts,
**update CLAUDE.md in the same pull request**; a stale architecture note is
worse than no note.

## Versioning and releases

The version is hardcoded in four places that drift if edited by hand, so bump it
with the `sync-version` skill (`.claude/skills/sync-version/`), which keeps
`pubspec.yaml` (`version:` **and** `msix_version:`), the About screen, the Inno
Setup installer default and CLAUDE.md in lockstep.

Releases are cut by dispatching `.github/workflows/release.yml`, which builds
the macOS DMG, the Windows installer and the portable ZIP, and drafts the GitHub
Release. User-facing changes get a line in [CHANGELOG.md](CHANGELOG.md) under
`Unreleased` as they land, not reconstructed at release time.

## Where documentation lives

| File | Audience |
|---|---|
| [README.md](README.md) | Someone deciding whether to use the app |
| [CHANGELOG.md](CHANGELOG.md) | Someone asking what changed between two versions |
| [CLAUDE.md](CLAUDE.md) | Someone about to change the code — architecture and invariants |
| [docs/](docs/) | The design and module specs the code is written against |

## License

By contributing you agree your work is licensed under the repository's
[MIT license](LICENSE).
