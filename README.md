# Jellyfin Media Management Tool

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue?style=for-the-badge)](https://flutter.dev/desktop)

A desktop app that renames and reorganizes a messy media folder into the layout
[Jellyfin expects](https://jellyfin.org/docs/general/server/media/naming/), and
writes the `.nfo` metadata and artwork to go with it.

It **never talks to a Jellyfin server** — there is no API client and no login.
Everything it does is local filesystem work, so it is equally useful for Emby,
Kodi, or a library you have not pointed a server at yet.

Windows, macOS and Linux. English and 中文.

## Install

Grab an installer from
[Releases](https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases):
a Windows installer or portable ZIP, or a macOS DMG. Linux is supported but not
yet published as a binary — [build it from source](#build-from-source).

## Organizing a folder

This is the main workflow, and it is deliberately a **three-step one with a stop
in the middle**:

1. **Point it at a folder.** Open a directory (or select part of one) and press
   Organize. Optionally give it a canonical title and say whether the folder is
   a movie or a series.
2. **Read the plan.** A language model works out what each group of files *is* —
   the title, movie or series, year, season, episode numbering — while the app's
   own code does everything that has a right answer: parsing episode numbers out
   of filenames, keeping subtitles and posters with the video they belong to,
   and spelling every destination path by Jellyfin's rules. **The model never
   writes a path.**
3. **Apply it, or don't.** The preview is the only dry run and the only gate.
   Every move is listed, every target is editable in place, and anything the
   model was unsure about is flagged and skipped rather than quietly guessed.
   Cancel and nothing has touched the disk.

Applying runs as a pausable, cancellable background task. A 26-episode series is
one decision, not 26 chances to spell a path differently, and a folder that is
too large for one request is decided in batches — a cancelled or failed run
resumes with only the groups it never got to.

### Undo

Every applied batch can record an undo manifest, and undoing walks the moves
back in reverse. Manifests are kept for 7 days. Corrections are remembered too —
a target you fixed in a preview you then applied stays fixed on the next run of
that folder.

## AI backends

Two wire protocols, which between them cover nearly everything:

- **OpenAI-compatible** `/chat/completions` — OpenAI, Azure, OpenRouter and
  other relays, and local servers: **LM Studio, Ollama, llama.cpp, vLLM**. A
  local server usually needs no API key at all, and pasting the URL it prints at
  startup is enough.
- **Google Generative Language API** `:generateContent`.

Several named profiles can coexist; the connection test is a real completion
rather than a model listing, because a server can list models happily while
rejecting every generation.

**Local models are a first-class target, not an afterthought.** The app ships
the sampling parameters model authors publish for their own families (Qwen,
DeepSeek-R1, Gemma, Mistral, GLM, Llama and more, each row citing its model
card), turns reasoning off by default — trying the several incompatible ways
servers spell that, and telling you if none of them took — and treats the
context window as a budget it must stay inside rather than a setting it can ask
for. Organizing needs a model that can **call tools**; the app probes for that
and says so plainly instead of failing halfway through a run.

## Metadata scraping

A second pipeline for filling in `.nfo` files and artwork. Give it a product
page URL and it extracts title, code, synopsis, cast and images, shows you a
field-by-field diff against whatever NFO is already on disk, and only writes
what you accept.

It tries the cheap routes first — embedded JSON-LD/OpenGraph, then a declarative
per-site recipe — and only pays for the model when there is nothing else to try.
A recipe the model writes is never saved without your say-so.

Artwork is picked from a grid of real thumbnails, and right-clicking a tile
assigns its Jellyfin role — `folder.jpg`, `backdrop.jpg` and so on — because
Jellyfin identifies artwork by file name. Saving images is its own action,
separate from writing metadata. Overwritten NFOs are really backed up, not just
logged.

A whole folder can be refreshed at once against the pages it was originally
scraped from.

## Browsing and previewing

- Multi-select, sorting, resizable columns, live directory watching.
- Video thumbnails rendered per platform (AVFoundation / Media Foundation /
  FFmpeg), cached on disk and keyed so a re-encode never shows a stale frame.
- Inline preview: video playback, zoomable images, monospaced text for subtitles
  and NFOs.
- Search sites you configure yourself, for looking a title up in a browser.
- Keyboard shortcuts throughout — the full table is in Settings → Shortcuts.

## Interface

A frosted-glass desktop shell with its own 48px title bar — its own window
buttons on Windows and Linux, the real traffic lights on macOS — light and dark
themes, and a user-chosen accent colour that previews live while you drag it.

The frost is not expensive. Both the window backdrop and the blur behind each
glass panel are pre-rendered, so a maximized 4K frame on an integrated GPU costs
the same whether the effect is on or off: **80.4 ms → 1.74 ms** per frame,
measured. A glass-intensity slider runs from full frost down to `0`, which
swaps every translucent surface for the design's pre-mixed opaque one — the
escape hatch for a weak GPU, and the only one you need.

English and 中文, with optional downloadable CJK UI fonts (HarmonyOS Sans SC,
MiSans) for machines whose system font is not to your taste.

## Not yet

The **Library** section (poster grid, filters, series detail) is drawn to the
design but not implemented — it needs a persisted library model the app does not
have. Other designed-but-unbuilt pieces are drawn as visibly disabled
placeholders rather than hidden or faked; each one is listed in
[`docs/spec/ui-redesign/backlog.md`](docs/spec/ui-redesign/backlog.md).

## Build from source

Requires the Flutter SDK (Dart `^3.10.4`; CI builds on Flutter 3.44.2).

```bash
git clone https://github.com/Joycai/Jellyfin-Media-Management-Tool.git
cd Jellyfin-Media-Management-Tool
flutter pub get
flutter run -d windows   # or macos / linux
```

Platform notes:

- **Linux** needs libmpv for video playback (`apt install libmpv-dev mpv`), plus
  system FFmpeg and libjpeg for thumbnails. Without them, previews and
  thumbnails degrade to icons; nothing else is affected.
- **Windows and macOS** bundle libmpv already.
- A Windows installer is built by running Inno Setup on
  [`scripts/inno_setup.iss`](scripts/inno_setup.iss) after `flutter build
  windows`; `dart run msix:create` produces an MSIX.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) has the setup, the build gates and the
conventions. [CLAUDE.md](CLAUDE.md) is the architecture document — the
invariants worth knowing before changing anything are in there, and it is kept
current. The design and module specs the code is written against are indexed in
[`docs/`](docs/), and [CHANGELOG.md](CHANGELOG.md) says what changed between
versions.

CI runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and
`flutter test` on every pull request. A lint *info* fails the build, so run all
three locally first.

## License

MIT — see [LICENSE](LICENSE).
