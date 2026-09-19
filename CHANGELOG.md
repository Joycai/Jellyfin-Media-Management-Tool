# Changelog

Notable, user-facing changes. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are the day the version was cut on `main`; the installers for it are on
the [Releases](https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases)
page. Entries are added under `Unreleased` as the change lands, not
reconstructed at release time.

## [Unreleased]

## [1.3.0] - 2026-09-19

### Added

- **AI access is now channels, routes and models.** A channel is one key on
  one host; it can speak several protocols (routes), and each model keeps its
  own parameters per route. Fourteen platforms come with their addresses and
  reasoning switches filled in, and each task (organize, learning a scrape
  recipe, direct extraction, frame recognition) can run on a different model.
  Existing settings are migrated on first read and send byte-identical
  requests.
- **Anthropic Messages and OpenAI Responses** protocols, alongside Chat
  Completions and Gemini. Signed thinking and encrypted reasoning go back to
  the model that wrote them, and only to it.
- **Frame recognition (opt-in, per model).** For videos whose names say
  nothing, the organizer can show a few frames to a model allowed image input
  and read the on-screen title. Off by default; a group decided this way is
  always marked for review.
- **API request log** (Settings → Privacy, off by default): every request body
  for 7 days, with no headers, keys or query strings.

### Fixed

- A blocked reply, a mid-stream failure or an error envelope inside an HTTP
  200 is reported as a failure instead of being read as an empty answer.
- A reply cut off at the output limit is reported as truncated, no longer as
  "this model cannot use tools".
- The connection test sends a request shaped like a real task, so a server
  that refuses tools fails the test instead of the first organize run.
- Zhipu, DeepSeek and Bailian use their own switches to turn reasoning off.
- Gemini now streams, and its API key moved from the URL to a header.
- What the app learned about a server (refused fields, JSON mode) is kept
  across restarts.

## [1.2.0] - 2026-09-16

### Added

- **Copy, cut, paste and move in the file browser.** Copy / Cut / Paste /
  Move to… in the row context menu, with ⌘C / ⌘X / ⌘V (Ctrl on Windows and
  Linux). Cut rows dim until pasted; the table footer shows the pending
  clipboard with a "Paste here" link. A paste never overwrites: a taken name
  asks to skip or keep both (`name (2).ext`). Every paste runs in the Tasks
  tab with byte progress and a Stop button, and can be undone from History.
  The clipboard is app-internal for now (no exchange with Finder / Explorer).

### Fixed

- Keyboard shortcuts marked as yielding to text fields (⌘A, Delete, F2, …)
  really do so now. They used to swallow the key when the search box had
  focus, so ⌘A selected files instead of the search text.

### Changed

- Repository layout: `lib/` is now organized by feature throughout, and `test/`
  mirrors it path for path. No behaviour changed — every moved library kept its
  API — but import paths did, so a branch started before this needs a rebase.
- New contributor documentation: `CONTRIBUTING.md`, this changelog, an index
  under `docs/`, and issue/PR templates. `CLAUDE.md` now states its rules
  briefly and keeps the reasoning in `docs/architecture/`.
- The conventions a linter can check are now enforced in
  `analysis_options.yaml` rather than only written down.

## [1.1.0] - 2026-09-13

### Changed

- **Performance mode is gone as a separate setting**, folded into the glass
  intensity slider's `0` stop — which is what it always meant. One control can
  no longer contradict itself: intensity `0` now swaps the translucent fills for
  the design's pre-mixed opaque surfaces instead of dropping the blur and
  leaving fills that read at roughly 2:1 contrast. An existing
  `performance_mode: true` migrates to intensity `0` on first load.

### Performance

- The window backdrop is baked into an image rather than redrawn: two
  full-window radial gradients cost more than the entire rest of the UI put
  together at 4K. Co-planar glass tiles also share one backdrop snapshot.
  Measured maximized at 3840x2160 on an integrated GPU: **80.4 ms → 32.0 ms**
  per frame.
- The glass blur itself is pre-rendered when the backdrop behind it is static,
  behind Settings → Appearance → Behavior → *Pre-render the glass blur* (on by
  default). Same measurement: **32.0 ms → 1.74 ms**, i.e. the frame now costs
  what an empty frame costs whether the frost is on or off, with 99.92% of
  pixels bit-identical to the live-filter render.
- Windows thumbnail extraction moved off the Flutter platform thread onto a
  native three-thread pool with WIC encoding. Entering a folder on a NAS had
  been serialising every frame behind the thread pumping the window's message
  loop — 21 ms → 46.6 ms per frame, with concurrency buying nothing.

### Fixed

- Title-bar content sat above centre on macOS.
- Assorted review findings from the 1.0.0 pass.

## [1.0.0] - 2026-09-12

First stable release: the organize pipeline (AI proposes, you review, only then
does anything touch disk, and every applied batch can be undone), the metadata
scrape pipeline, the file browser with per-platform video thumbnails, and the
redesigned frosted-glass desktop shell with light/dark themes, a live-previewing
accent colour and English/中文 localization.

Changes before this point were not tracked in this file; the git log and the
[Releases](https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases)
page have them.

[Unreleased]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/compare/main...HEAD
[1.3.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.2.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.1.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.0.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
