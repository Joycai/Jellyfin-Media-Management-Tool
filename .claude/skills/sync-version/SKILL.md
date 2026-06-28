---
name: sync-version
description: >-
  Bump or set the app version for this Jellyfin Media Management Tool repo and
  sync it across every hardcoded copy (pubspec.yaml, the About-screen
  _appVersion constant, the Inno Setup installer default, and the CLAUDE.md doc
  line) in one consistent pass. Use this WHENEVER the user wants to change,
  bump, release, or tag a new version — e.g. "bump the version to 1.0.0",
  "release a new patch", "set version to 1.2.0+3", "cut a minor release",
  "why does the About screen show an old version", or any time the version
  numbers across the project look out of sync. Reach for it even if the user
  only says "bump version" without naming the files — keeping the scattered
  copies in lockstep is exactly what this skill exists to prevent drift on.
---

# Sync version

This Flutter desktop repo keeps its version (`X.Y.Z+N`) in several places. One is
the real source of truth; the rest are hardcoded copies that silently drift when
someone bumps one and forgets the others — which is how the About screen ends up
showing a stale version. This skill bumps or sets the version and rewrites every
hardcoded copy together.

## How to use it

Run the bundled script from anywhere in the repo. It locates the repo root by
finding `pubspec.yaml`, so the working directory doesn't matter.

```bash
python3 .claude/skills/sync-version/scripts/sync_version.py <spec>
```

`<spec>` is either an explicit version or a bump keyword:

| Spec | Meaning | Example result from `0.9.0+1` |
|------|---------|-------------------------------|
| `patch` | bump Z, increment build | `0.9.1+2` |
| `minor` | bump Y, reset Z, increment build | `0.10.0+2` |
| `major` | bump X, reset Y/Z, increment build | `1.0.0+2` |
| `build` | keep name, increment build only | `0.9.0+2` |
| `1.2.0` | set name, auto-increment build | `1.2.0+2` |
| `1.2.0+5` | set name and build exactly | `1.2.0+5` |

A version change is treated as a bump, so an explicit name without `+N` still
advances the build number. Pass an explicit `+N` when you need to control it.

**Recommended flow:**

1. Confirm what the user wants. If it's ambiguous ("bump the version"), default
   to `patch` but say so. If they name a target version, use it verbatim.
2. Preview first with `--dry-run` and show the user the planned changes:
   ```bash
   python3 .claude/skills/sync-version/scripts/sync_version.py --dry-run <spec>
   ```
3. Apply it by running the same command without `--dry-run`.
4. Verify (see below) and report the new version plainly.

To just read the current version: `... sync_version.py --show`.

## What it touches

Updates these hardcoded copies:

- `pubspec.yaml` — `version: X.Y.Z+N` (the source of truth; full string)
- `lib/widgets/settings/settings_screen.dart` — `_appVersion = 'X.Y.Z'` (About screen; name only)
- `scripts/inno_setup.iss` — `#define MyAppVersion "X.Y.Z"` (installer default; name only)
- `CLAUDE.md` — the `Current app version:` doc line (full string)

## What it deliberately leaves alone

Do **not** hand-edit these, and don't be surprised the script skips them — they
derive the version from `pubspec.yaml` at build time, so editing them would
create a second source of truth and reintroduce the drift this skill prevents:

- macOS `macos/Runner/Info.plist` → `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`
- Windows `windows/runner/Runner.rc` + `CMakeLists.txt` → `FLUTTER_VERSION*`
- Linux `linux/**/CMakeLists.txt`
- CI `.github/workflows/release.yml` reads the version straight from `pubspec.yaml`

## Verifying

After applying, confirm no stale copy survived. Replace `0.9.0` with the *old*
version name:

```bash
grep -rn "0\.9\.0" --include="*.dart" --include="*.yaml" --include="*.iss" \
  --include="*.md" --exclude-dir=.git --exclude-dir=build --exclude-dir=.dart_tool .
```

The only legitimate hits should be in `pubspec.lock` (dependency hashes, unrelated)
or historical changelog entries. If a real copy turns up somewhere new, add it to
the `TARGETS` list in `scripts/sync_version.py` so it's covered next time.

The script also exits non-zero and prints a `WARNING` if one of its expected
targets has gone missing (e.g. a file was renamed or the surrounding code changed
so the pattern no longer matches) — treat that as a signal to update `TARGETS`,
not as a transient error to ignore.

## Notes

- The edits are plain text-substitution and safe to re-run; running the same spec
  twice is a no-op.
- This does not commit or tag. If the user wants a release commit/tag, do that as
  a separate, explicit step after they've reviewed the diff.
