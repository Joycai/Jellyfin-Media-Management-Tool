#!/usr/bin/env python3
"""Synchronize the app version across every hardcoded location in this repo.

The source of truth is pubspec.yaml's `version: X.Y.Z+N`. A handful of other
files hardcode their own copy of that string and silently drift when someone
bumps pubspec but forgets them. This script reads the current version, computes
the target, and rewrites all the hardcoded copies in one atomic pass.

It deliberately does NOT touch the platform files that derive the version from
pubspec at build time (macOS Info.plist via $(FLUTTER_BUILD_NAME), Windows
Runner.rc via FLUTTER_VERSION*, Linux CMakeLists). Editing those would create a
*second* source of truth — exactly the drift we're trying to avoid.

Usage:
    sync_version.py <version|bump>   e.g. 1.2.0 | 1.2.0+5 | patch | minor | major | build
    sync_version.py --dry-run <...>  show the planned changes without writing
    sync_version.py --show           print the current version and exit
"""

import argparse
import os
import re
import sys

# Each target: (relative path, regex, builder). The regex must have exactly two
# capture groups bracketing the version text so we can swap only that slice and
# leave surrounding syntax untouched. `kind` decides whether the slot wants the
# name only ("X.Y.Z") or the full string with build number ("X.Y.Z+N").
TARGETS = [
    # The canonical source. Anchored to the start of a line so it can't match
    # the `version:` keys of dependencies further down the file.
    ("pubspec.yaml", re.compile(r"(?m)^(version:\s*)(\S+)$"), "full"),
    # About screen, shown to users. Name only — no build number on the UI.
    (
        "lib/widgets/settings/settings_screen.dart",
        re.compile(r"(_appVersion\s*=\s*')([^']*)(')"),
        "name",
    ),
    # Inno Setup installer default (CI overrides via /DMyAppVersion, but local
    # `iscc` runs fall back to this literal). Name only.
    (
        "scripts/inno_setup.iss",
        re.compile(r'(#define MyAppVersion\s*")([^"]*)(")'),
        "name",
    ),
    # Documentation line in CLAUDE.md. Full string inside backticks.
    (
        "CLAUDE.md",
        re.compile(r"(Current app version:\s*`)([^`]*)(`)"),
        "full",
    ),
]

VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")
BUMPS = {"major", "minor", "patch", "build"}


def find_repo_root(start):
    """Walk up from `start` until we find the pubspec.yaml that anchors the repo."""
    d = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(d, "pubspec.yaml")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            sys.exit("error: could not locate pubspec.yaml in any parent directory")
        d = parent


def read_current(root):
    """Return (name, build) parsed from pubspec.yaml, e.g. ('0.9.0', 1)."""
    text = open(os.path.join(root, "pubspec.yaml"), encoding="utf-8").read()
    m = re.search(r"(?m)^version:\s*(\S+)$", text)
    if not m:
        sys.exit("error: no `version:` line found in pubspec.yaml")
    vm = VERSION_RE.match(m.group(1))
    if not vm:
        sys.exit(f"error: pubspec version '{m.group(1)}' is not X.Y.Z(+N)")
    major, minor, patch, build = vm.groups()
    return (f"{major}.{minor}.{patch}", int(build) if build else 0)


def resolve_target(arg, cur_name, cur_build):
    """Turn the user's arg into a (name, build) tuple.

    - bump keyword: derive from current; major/minor/patch reset lower parts and
      increment build; `build` keeps the name and only bumps the build number.
    - explicit X.Y.Z: treat as a bump — auto-increment build from current.
    - explicit X.Y.Z+N: take exactly what the user wrote.
    """
    if arg in BUMPS:
        major, minor, patch = (int(p) for p in cur_name.split("."))
        if arg == "major":
            major, minor, patch = major + 1, 0, 0
        elif arg == "minor":
            minor, patch = minor + 1, 0
        elif arg == "patch":
            patch += 1
        return (f"{major}.{minor}.{patch}", cur_build + 1)

    vm = VERSION_RE.match(arg)
    if not vm:
        sys.exit(
            f"error: '{arg}' is neither a bump keyword "
            f"({'/'.join(sorted(BUMPS))}) nor a X.Y.Z(+N) version"
        )
    major, minor, patch, build = vm.groups()
    name = f"{major}.{minor}.{patch}"
    if build is not None:
        return (name, int(build))
    # Explicit name without +N: a version change is a bump, so advance build.
    return (name, cur_build + 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("spec", nargs="?", help="version (1.2.0 / 1.2.0+5) or bump (major/minor/patch/build)")
    ap.add_argument("--dry-run", action="store_true", help="show planned edits without writing")
    ap.add_argument("--show", action="store_true", help="print current version and exit")
    args = ap.parse_args()

    root = find_repo_root(os.getcwd())
    cur_name, cur_build = read_current(root)
    cur_full = f"{cur_name}+{cur_build}"

    if args.show:
        print(cur_full)
        return

    if not args.spec:
        ap.error("a version or bump keyword is required (or use --show)")

    new_name, new_build = resolve_target(args.spec, cur_name, cur_build)
    new_full = f"{new_name}+{new_build}"
    slot = {"name": new_name, "full": new_full}

    print(f"Current: {cur_full}")
    print(f"Target:  {new_full}\n")

    changed = []
    missing = []
    for rel, pattern, kind in TARGETS:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            missing.append(rel)
            continue
        text = open(path, encoding="utf-8").read()
        m = pattern.search(text)
        if not m:
            missing.append(rel)
            continue
        old_slice = m.group(2)
        new_slice = slot[kind]
        groups = m.groups()
        # Rebuild the matched span with the middle group replaced.
        new_match = groups[0] + new_slice + "".join(groups[2:])
        new_text = text[: m.start()] + new_match + text[m.end():]
        status = "ok" if old_slice != new_slice else "unchanged"
        print(f"  [{status}] {rel}: {old_slice!r} -> {new_slice!r}")
        if not args.dry_run and new_text != text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new_text)
        if old_slice != new_slice:
            changed.append(rel)

    if missing:
        print("\nWARNING: these expected targets were not found (pattern moved?):")
        for rel in missing:
            print(f"  - {rel}")

    print()
    if args.dry_run:
        print(f"DRY RUN — no files written. {len(changed)} file(s) would change.")
    else:
        print(f"Done. Updated {len(changed)} file(s) to {new_full}.")
    if missing:
        # Non-zero so callers/CI notice a target silently disappeared.
        sys.exit(2)


if __name__ == "__main__":
    main()
