#!/usr/bin/env bash
# Fails when the hardcoded version copies disagree with pubspec.yaml.
# The copies are the ones the sync-version skill maintains
# (.claude/skills/sync-version/SKILL.md); run that skill to fix a mismatch.
set -euo pipefail
cd "$(dirname "$0")/.."

full=$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml)
name=${full%%+*}

about=$(sed -nE "s/.*_appVersion = '([^']+)'.*/\1/p" lib/widgets/settings/settings_screen.dart)
inno=$(sed -nE 's/^[[:space:]]*#define MyAppVersion "([^"]+)".*/\1/p' scripts/inno_setup.iss)
msix=$(sed -nE 's/^[[:space:]]*msix_version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml)
# shellcheck disable=SC2016  # the backticks are literal Markdown, not a command
doc=$(sed -nE 's/.*Current app version: `([^`]+)`.*/\1/p' CLAUDE.md)

status=0
check() { # label actual expected
  if [ "$2" = "$3" ]; then
    echo "ok    $1: $2"
  else
    echo "DRIFT $1: $2 (expected $3)"
    status=1
  fi
}
check "pubspec.yaml version" "$full" "${full:-<missing>}"
check "settings_screen.dart _appVersion" "$about" "$full"
check "inno_setup.iss MyAppVersion" "$inno" "$name"
check "pubspec.yaml msix_version" "$msix" "$name.0"
check "CLAUDE.md doc line" "$doc" "$full"

if [ "$status" -ne 0 ]; then
  echo "Version copies have drifted; run the sync-version skill." >&2
fi
exit "$status"
