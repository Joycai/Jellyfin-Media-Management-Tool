# Changelog

Notable, user-facing changes. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are the day the version was cut on `main`; the installers for it are on
the [Releases](https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases)
page. Entries are added under `Unreleased` as the change lands, not
reconstructed at release time.

## [Unreleased]

## [1.3.3] - 2026-09-28

### Changed

- With reasoning off, GLM-5.3 on Zhipu's OpenAI-compatible route is now
  asked for the least reasoning (`reasoning_effort: low`) once it has said
  it cannot stop, instead of being left to reason at its default. In tests
  that cut its reasoning from 230–1,500 tokens to 0–130 per request, and it
  still decided every group alike, though it sometimes left out a year it
  would otherwise have given. The model page, the capability matrix and the
  route-switch dialog name the field. A model that refuses the least as well
  runs at its default and is shown as always reasoning.

## [1.3.2] - 2026-09-28

### Fixed

- Turning reasoning off on DeepSeek's, Alibaba Cloud Model Studio's and Zhipu's
  Anthropic-compatible routes now really turns it off: those servers think
  unless told not to, and the app used to send nothing for off there. A
  model that cannot stop (GLM-5.3; MiniMax-M2.5 and GLM through Model
  Studio) is remembered as such after one request, and from then on is
  asked for the least reasoning when reasoning is off
  (`output_config.effort: low`). GLM-5.3 on Zhipu then stops reasoning in
  tests; GLM-5.3-Flash, and MiniMax-M2.5 through Model Studio, still reason
  a little. The model page, the capability matrix, the route-switch dialog
  and Diagnostics say so, and the reasoning toggle stays usable. A model
  that refuses the least as well runs at its default and is shown as always
  reasoning.
- The connection test no longer reports reasoning that would not turn off
  for a server that returns an empty thinking block when reasoning is not
  asked for or turned off.
- A model family that reasons however it is asked (DeepSeek-R1, QwQ, the
  Qwen3 Thinking models; gpt-oss, which can only be lowered) is no longer
  described as "off by default", or as having a switch, in the model page
  or the capability matrix.

## [1.3.1] - 2026-09-28

### Added

- Linux builds. Each release now also attaches a `.tar.gz` of the Linux app
  bundle next to the macOS DMG and the Windows installer. It needs libmpv,
  FFmpeg and libjpeg from the system for playback and thumbnails.

### Changed

- The reasoning switch means the same thing on every protocol. A model family
  that always reasons (DeepSeek-R1, QwQ, the Thinking-2507 models) or never
  does (Qwen3's Instruct models, Gemma 3, Llama 3) is now asked for the mode
  it runs in on Messages, Responses and Gemini routes too, as it already was
  on Chat Completions and as the model page has always shown; on a Messages
  route that also means a family that always reasons goes without its
  sampling values, as any model does there while it reasons. gpt-oss, whose
  switch is locked, is asked for its least reasoning whatever an old saved
  choice said — on Responses, where it was asked for none or medium, and on
  Chat Completions without a platform switch, where an old "on" left it at
  the server's default. The
  route-switch dialog and Diagnostics read that same choice.

### Fixed

- A Messages route told off with its sampling values beside it now learns
  the right thing from a refusal that mentions both. "reasoning_effort is
  not supported; use temperature instead" gives thinking up and keeps the
  value (it used to drop the value first, for a month); "temperature is not
  supported with thinking" drops the value and keeps saying off (it used to
  give thinking up). A field named only inside the error's echo of the
  request is no longer taken as refused, and an error that refuses another
  field and then, in a sentence of its own, points at the thinking
  documentation no longer makes the route give reasoning up.
- A Messages route behind a relay that translates the request for thinking
  into its upstream's field and refuses it under that name
  (`reasoning_effort`, `chat_template_kwargs`, Gemini's `thinkingConfig`) no
  longer fails every request. The refusal is read as the `thinking` field
  itself refused: it is left off that route's requests both ways and the
  model runs at its default. A model family whose reasoning cannot be turned
  off was stuck there before, since its switch is locked.
- Frame recognition no longer waits on a stuck vision service five times
  over: a lookup that times out is the last one of that run, later batches
  are not offered it, and a request whose reply never starts is closed rather
  than left open behind the next one.
- The line under the reasoning switch no longer tells users of a cloud route
  to turn thinking off in the server's own settings. That advice is kept for
  the user's own server — an address on this computer or a private network;
  a vendor's or a relay's route on a public name is told turning it off has
  no effect there; and where the two disagree, or a custom channel sits on a
  public name, the line says both.
- The window background looked mottled, like a dishcloth, on high-DPI displays
  — most visible in the middle pane before a folder is open. The backdrop is
  rendered once at a reduced size and stretched back over the window, and the
  reduction was measured in layout units rather than real screen pixels, so a
  2x display silently doubled it; the stretch then magnified the gradient's own
  dithering into visible blobs. The reduction is now measured in screen pixels
  and is smaller besides, so the backdrop is rendered four times as densely as
  before on a 2x display, twice on a 1x one.
- Drop-down menus (task assignment, platform, model pickers, subtitle and
  season dialogs) were see-through over the frosted background; they now use
  the same opaque fill as other menus.

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
[1.3.2]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.3.1]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.3.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.2.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.1.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
[1.0.0]: https://github.com/Joycai/Jellyfin-Media-Management-Tool/releases
