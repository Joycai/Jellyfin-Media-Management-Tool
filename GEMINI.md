# GEMINI.md — Jellyfin Media Management Tool

**Read [CLAUDE.md](CLAUDE.md). It is the project's only architecture document,
and everything in it applies to you.**

This file used to carry its own copy of that guidance. It drifted: by the time
anyone noticed, it was naming a `GlassTheme` extension that no longer exists, a
`lib/services/ai/ai_prompt.dart` that had been deleted, seven services where
there are nine, and — worst of it — calling
`lib/widgets/dialogs/{tv_show,part,subtitle}_dialog.dart` "remnants of the old
manual rename workflow" when all three are live code on the AI preview path. An
agent trusting that sentence would have deleted working features.

Two hand-maintained copies of one architecture is how that happens, so there is
now one copy. Anything worth writing down about this codebase goes in
`CLAUDE.md`.

## Before you push

CI (`.github/workflows/pr-check.yml`) runs all three of these on every PR to
`main`, and a lint *info* fails the build, not just an error:

```bash
dart format --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```
