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
  ALSO reach for it when starting work that will ship: creating a feature or
  bugfix branch, opening a release PR, or preparing a tag. A PreToolUse hook
  raises the version question at branch creation, and this skill is what
  answers it — see "Branch-creation prompt" below for what to do when that
  reminder fires, including when the right answer is to not bump at all.
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

## Branch-creation prompt

A `PreToolUse` hook (`scripts/branch_version_hook.py`, registered against the
Bash tool in `.claude/settings.json`) watches for `git checkout -b` /
`git switch -c` and injects a reminder naming the new branch, the current
version, and the bump level its prefix implies.

The hook only notices; it never bumps. That separation is deliberate — see
"When *not* to bump" below for why applying a bump at branch creation is
usually the wrong move.

**When the reminder fires:**

1. Ask once, in a single sentence, folded into whatever you were already
   saying. It is a question in passing, not a ceremony — the user is in the
   middle of starting work and does not want a checklist.
2. Take no for an answer. If they decline, or just ignore it and move on, drop
   it permanently for this branch. Re-raising it later is the fastest way to
   make someone disable the hook.
3. If they say yes, follow the normal flow above (`--dry-run`, show, apply).
   Treat the prefix-derived level as a starting suggestion, not a verdict — a
   `fix/` branch that changes user-visible behaviour may well deserve `minor`.

**What the hook stays quiet about**, so its speaking up stays meaningful:
`chore/`, `ci/`, `docs/`, `test/`, `style/`, `build/` prefixes (no shipped
change); branches whose name contains `bump`, `release`, or `version` (those
*are* the version change — asking would loop); any Bash command that is not
branch creation; and any repo without a `pubspec.yaml` above the cwd.

An unrecognised prefix still prompts, but without a suggested level — a wrong
suggestion is worse than none.

To silence it entirely, remove the `PreToolUse` block from
`.claude/settings.json`. The skill keeps working; only the automatic nudge goes
away.

## When *not* to bump

The pressure this skill exists to resist is drift between copies of the version.
It is not "every branch gets a number". Bumping at branch-creation time costs
more than it looks:

- **Parallel branches collide.** Every open branch that bumped now edits
  `version:` in `pubspec.yaml`, so they conflict with each other on merge — for
  a line whose final value only the last merge actually decides.
- **The history gets noisier than the releases.** Three branches merged for one
  release produce three version numbers where users only ever saw one.

The cheaper default is to bump **once, at release time**, after the work that
ships together has landed, and pick the level from the largest change in the
batch. A branch-time bump earns its keep when the branch *is* the release — a
hotfix going straight out, or a release-prep branch.

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
