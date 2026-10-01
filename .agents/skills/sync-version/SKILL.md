---
name: sync-version
description: >-
  Set or bump the app version and synchronize its hardcoded copies in this
  repository. Use for version changes, release preparation, version drift,
  or a branch-version reminder. Branch creation alone does not authorize a bump.
---

# Sync version

`pubspec.yaml` is the source of truth (`X.Y.Z+N`). The bundled script updates
its version and MSIX version, the About-screen constant, the Inno Setup default,
and the current-version line in `AGENTS.md` together.

## Workflow

Run from anywhere inside the repository (Python 3 is required). Use `python`
on Windows and `python3` on macOS/Linux. The paths below are relative to the
repository root; from a subdirectory resolve that root with `git rev-parse
--show-toplevel`.

```bash
python3 .agents/skills/sync-version/scripts/sync_version.py --show
python3 .agents/skills/sync-version/scripts/sync_version.py --dry-run <spec>
python3 .agents/skills/sync-version/scripts/sync_version.py <spec>
```

1. Use the requested version verbatim. For an unspecified bump, default to
   `patch` and state that assumption. Existing authorization is sufficient.
2. Preview with `--dry-run`, inspect every target, then apply the same spec.
3. Run `bash scripts/check_version_sync.sh` and review the diff. Missing targets
   cause exit code 2; update the target paths/patterns rather than ignoring it.
4. Report the resulting version. Commit, tag or publish only within the user's
   requested scope.

| Spec | Effect from `0.9.0+1` |
|---|---|
| `patch` | `0.9.1+2` |
| `minor` | `0.10.0+2` |
| `major` | `1.0.0+2` |
| `build` | `0.9.0+2` |
| `1.2.0` | `1.2.0+2` (name without a build increments the current build) |
| `1.2.0+5` | `1.2.0+5` (exact target) |

Reapplying an explicit version **with** `+N` is a no-op. Bump keywords and a
version without `+N` increment the build again on each invocation.

## Branch-version reminder

`.codex/hooks.json` registers `.codex/hooks/branch_version_hook.py` as a
`PreToolUse` hook for shell tools. It recognizes `git checkout -b` / `git switch
-c` (including force variants) and only emits context; it never modifies files.
The commands resolve the hook from the Git root so it also works from a
subdirectory. On Windows the configuration uses `python`; other platforms use
`python3`.

Review and trust the hook with `/hooks` in Codex CLI before relying on it.
Removing its `PreToolUse` entry disables automatic reminders; version checks
in CI and this skill continue to work.

A `codex/` namespace is stripped before classifying the branch. `feat/` or
`feat-` suggests minor; `fix`, `bugfix`, `hotfix`, `perf`, and `refactor` suggest
patch. `chore`, `ci`, `docs`, `test`, `style`, and `build` stay quiet. Branches
containing a `bump`, `release`, or `version` word also stay quiet. An unknown
prefix produces a reminder without guessing a level.

When a reminder appears, use the conversation's existing authorization. If a
version choice is still missing, ask once briefly while continuing independent
work. If the user already declined, or ignores the suggestion and moves on,
drop it for the branch. Do not bump automatically.

The default is to bump once at release time after the work shipping together
has landed. Bumping every branch creates version conflicts and numbers users
never see. Branch-time bumps are useful for a hotfix or release-prep branch
when the user requests one. Documentation and tooling migrations need no bump.

## Targets

- `pubspec.yaml`: full version and `msix_version` (`X.Y.Z.0`).
- `lib/widgets/settings/settings_screen.dart`: `_appVersion`, full version.
- `scripts/inno_setup.iss`: `MyAppVersion`, name only.
- `AGENTS.md`: `Current app version:`, full version.

Do not edit platform version fields derived at build time: macOS `Info.plist`
uses `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`; Windows uses
`FLUTTER_VERSION*`; Linux and release CI derive their versions from pubspec.

The behavioral scenarios are in `evals/evals.json`. Automated script and hook
regressions run with `python -m unittest discover -s scripts/tests`.
