#!/usr/bin/env python3
"""PreToolUse hook: notice branch creation and surface the version question.

Registered against the Bash tool in .claude/settings.json. Most Bash calls are
not branch creation, so the hook stays silent unless it recognises one — a hook
that speaks up on every command trains everyone to ignore it.

It deliberately does not run sync_version.py. Bumping is a judgement call that
depends on what the branch turns out to contain, and applying it at creation
time makes every parallel branch fight over pubspec.yaml. The hook's whole job
is to make sure the question gets asked once, at the moment the answer is
cheapest to act on.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# `git checkout -b NAME`, `git switch -c NAME`, and the force variants (-B/-C),
# with flags in any order before the name.
_BRANCH_CMD = re.compile(
    r"\bgit\s+(?:checkout|switch)\s+(?:-\S+\s+)*-[bBcC]\s+(?P<name>[^\s;&|]+)"
)

# Branch prefix → the bump level it usually implies. The mapping mirrors
# Conventional Commits because that is what this repo's branch names already
# follow; anything unrecognised falls through to "ask without a suggestion"
# rather than guessing, since a wrong suggestion is worse than none.
_LEVEL_BY_PREFIX = {
    "feat": "minor",
    "feature": "minor",
    "fix": "patch",
    "bugfix": "patch",
    "hotfix": "patch",
    "perf": "patch",
    "refactor": "patch",
    # Housekeeping that ships no user-visible change — flagging these would be
    # noise, so the hook says nothing at all for them.
    "chore": None,
    "ci": None,
    "docs": None,
    "test": None,
    "style": None,
    "build": None,
}

_VERSION_RE = re.compile(r"^version:\s*(?P<version>\S+)", re.MULTILINE)


def find_repo_root(start: Path) -> Path | None:
    """Walk up from `start` looking for pubspec.yaml, the version's home."""
    for candidate in (start, *start.parents):
        if (candidate / "pubspec.yaml").is_file():
            return candidate
    return None


def current_version(root: Path) -> str | None:
    try:
        text = (root / "pubspec.yaml").read_text(encoding="utf-8")
    except OSError:
        return None
    match = _VERSION_RE.search(text)
    return match.group("version") if match else None


def build_message(branch: str, root: Path) -> str | None:
    """The reminder text, or None when this branch does not warrant one."""
    prefix = branch.split("/", 1)[0].lower() if "/" in branch else ""

    # A branch created *by* this workflow already is the version change; asking
    # again would loop.
    if re.search(r"\b(bump|release|version)\b", branch, re.IGNORECASE):
        return None

    if prefix in _LEVEL_BY_PREFIX:
        level = _LEVEL_BY_PREFIX[prefix]
        if level is None:
            return None
        suggestion = (
            f"The `{prefix}/` prefix suggests a **{level}** bump, "
            f"but confirm rather than assume — the right level depends on what "
            f"the branch actually ends up containing."
        )
    else:
        suggestion = (
            "The branch name does not follow a known prefix, so there is no "
            "obvious bump level — ask which one applies, or whether this branch "
            "needs a version change at all."
        )

    version = current_version(root) or "unknown"
    script = ".claude/skills/sync-version/scripts/sync_version.py"

    return (
        f"About to create branch `{branch}`. Current version: `{version}`.\n\n"
        f"{suggestion}\n\n"
        "Ask the user — in one short sentence, as part of your next reply — "
        "whether this branch should carry a version bump. Do not run "
        f"`{script}` unless they say yes; bumping on every branch makes "
        "parallel branches collide in pubspec.yaml, and many changes are best "
        "released together under a single version. If they decline, drop it "
        "and do not raise it again for this branch.\n\n"
        "If they say yes, use the sync-version skill so every hardcoded copy "
        "moves together."
    )


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # Malformed input is the harness's problem, not a reason to fail.

    # Both shells reach git on this repo's platforms, and each carries the
    # command under the same `tool_input.command` key.
    if payload.get("tool_name") not in ("Bash", "PowerShell"):
        return 0

    command = (payload.get("tool_input") or {}).get("command") or ""
    match = _BRANCH_CMD.search(command)
    if not match:
        return 0

    cwd = payload.get("cwd") or "."
    root = find_repo_root(Path(cwd).resolve())
    if root is None:
        return 0  # Not this repo — the version layout the skill knows is absent.

    # Quotes survive the regex when the command was itself quoted (e.g. a branch
    # name inside a shell string), and would show up verbatim in the reminder.
    branch = match.group("name").strip("\"'")
    if not branch:
        return 0

    message = build_message(branch, root)
    if message is None:
        return 0

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": message,
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
