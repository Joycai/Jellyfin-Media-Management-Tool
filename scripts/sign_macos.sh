#!/usr/bin/env bash
# Signs and optionally notarizes the macOS Release .app bundle and .dmg.
# Used both locally and by .github/workflows/release.yml.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/sign_macos.sh sign-app [options]
  scripts/sign_macos.sh sign-dmg --dmg <path> [options]
  scripts/sign_macos.sh notarize --target <path> <auth-options> [--no-staple]

Subcommands:
  sign-app   Inside-out codesign with Hardened Runtime + timestamp + Release entitlements.
    --identity <name>      Signing identity (default: $MACOS_SIGN_IDENTITY)
    --app <path>           .app bundle (default: build/macos/Build/Products/Release/Jellyfin Media Management Tool.app)
    --entitlements <path>  Entitlements plist (default: macos/Runner/Release.entitlements)
    --keychain <path>      Optional keychain path passed to codesign

  sign-dmg   Codesign a .dmg disk image with timestamp and verify it.
    --dmg <path>           .dmg file (required)
    --identity <name>      Signing identity (default: $MACOS_SIGN_IDENTITY)
    --keychain <path>      Optional keychain path passed to codesign

  notarize   Submit an .app (auto-zipped), .dmg, or .zip to Apple notarytool and staple.
    --target <path>        .dmg, .app, or .zip to notarize (required)
    --profile <name>       Keychain profile stored via `xcrun notarytool store-credentials`
    --api-key <p8-path>    App Store Connect API key (.p8) path (with --api-key-id & --api-issuer)
    --api-key-id <id>      App Store Connect API Key ID
    --api-issuer <uuid>    App Store Connect Issuer ID
    --apple-id <email>     Apple ID (with --apple-password & --team-id)
    --apple-password <pw>  App-specific password
    --team-id <id>         Apple Developer Team ID
    --no-staple            Skip `xcrun stapler staple` (default for .zip)

Examples:
  # Local sign after `flutter build macos --release`
  scripts/sign_macos.sh sign-app \
    --identity "Developer ID Application: Cai Zhengxu (H9WK585493)"

  # Local sign + notarize DMG using a stored notarytool keychain profile
  scripts/sign_macos.sh sign-dmg --dmg dist/jellyfin-media-management-tool-1.3.4-macos.dmg \
    --identity "Developer ID Application: Cai Zhengxu (H9WK585493)"
  scripts/sign_macos.sh notarize --target dist/jellyfin-media-management-tool-1.3.4-macos.dmg \
    --profile "notary-profile"
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

# Sort NUL-delimited paths deepest-first so nested Mach-O binaries are signed
# before their enclosing bundles.
sort_deepest_first() {
  python3 -c '
import sys
paths = [p for p in sys.stdin.buffer.read().split(b"\0") if p]
paths.sort(key=lambda p: p.count(b"/"), reverse=True)
sys.stdout.buffer.write(b"".join(p + b"\0" for p in paths))
'
}

cmd_sign_app() {
  local identity="${MACOS_SIGN_IDENTITY:-}"
  local app="build/macos/Build/Products/Release/Jellyfin Media Management Tool.app"
  local entitlements="macos/Runner/Release.entitlements"
  local keychain=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      --app) app="${2:-}"; shift 2 ;;
      --entitlements) entitlements="${2:-}"; shift 2 ;;
      --keychain) keychain="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option for sign-app: $1" ;;
    esac
  done

  [ -n "$identity" ] || die "Signing identity is required (--identity or MACOS_SIGN_IDENTITY)."
  [ -d "$app" ] || die "App bundle not found: $app"
  [ -f "$entitlements" ] || die "Entitlements file not found: $entitlements"

  local -a keychain_args=()
  if [ -n "$keychain" ]; then
    keychain_args=(--keychain "$keychain")
  fi

  local -a common_flags=(--force --sign "$identity" --options runtime --timestamp)
  if [ "${#keychain_args[@]}" -gt 0 ]; then
    common_flags+=("${keychain_args[@]}")
  fi

  echo "Signing standalone shared libraries in $app..."
  while IFS= read -r -d '' item; do
    codesign "${common_flags[@]}" "$item"
  done < <(find "$app/Contents" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | sort_deepest_first)

  echo "Signing nested bundles (.xpc/.appex/.app) in $app..."
  while IFS= read -r -d '' item; do
    codesign "${common_flags[@]}" "$item"
  done < <(find "$app/Contents" -mindepth 1 -type d \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) -print0 | sort_deepest_first)

  if [ -d "$app/Contents/Frameworks" ]; then
    echo "Signing frameworks in $app/Contents/Frameworks..."
    while IFS= read -r -d '' fw; do
      codesign "${common_flags[@]}" "$fw"
    done < <(find "$app/Contents/Frameworks" -type d -name "*.framework" -print0 | sort_deepest_first)
  fi

  echo "Signing main app bundle $app..."
  codesign "${common_flags[@]}" --entitlements "$entitlements" "$app"

  echo "Verifying app signature..."
  codesign --verify --deep --strict --verbose=2 "$app"
}

cmd_sign_dmg() {
  local dmg=""
  local identity="${MACOS_SIGN_IDENTITY:-}"
  local keychain=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dmg) dmg="${2:-}"; shift 2 ;;
      --identity) identity="${2:-}"; shift 2 ;;
      --keychain) keychain="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option for sign-dmg: $1" ;;
    esac
  done

  [ -n "$dmg" ] || die "--dmg is required."
  [ -f "$dmg" ] || die "DMG not found: $dmg"
  [ -n "$identity" ] || die "Signing identity is required (--identity or MACOS_SIGN_IDENTITY)."

  local -a args=(--force --sign "$identity" --timestamp)
  if [ -n "$keychain" ]; then
    args+=(--keychain "$keychain")
  fi

  echo "Signing DMG $dmg..."
  codesign "${args[@]}" "$dmg"

  echo "Verifying DMG signature..."
  codesign --verify --strict --verbose=2 "$dmg"
}

cmd_notarize() {
  local target=""
  local profile=""
  local api_key=""
  local api_key_id=""
  local api_issuer=""
  local apple_id=""
  local apple_password=""
  local team_id=""
  local staple="true"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target) target="${2:-}"; shift 2 ;;
      --profile) profile="${2:-}"; shift 2 ;;
      --api-key) api_key="${2:-}"; shift 2 ;;
      --api-key-id) api_key_id="${2:-}"; shift 2 ;;
      --api-issuer) api_issuer="${2:-}"; shift 2 ;;
      --apple-id) apple_id="${2:-}"; shift 2 ;;
      --apple-password) apple_password="${2:-}"; shift 2 ;;
      --team-id) team_id="${2:-}"; shift 2 ;;
      --no-staple) staple="false"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option for notarize: $1" ;;
    esac
  done

  [ -n "$target" ] || die "--target is required."
  [ -e "$target" ] || die "Target not found: $target"

  local -a auth_args=()
  local auth_count=0
  if [ -n "$profile" ]; then
    auth_count=$((auth_count + 1))
    auth_args=(--keychain-profile "$profile")
  fi
  if [ -n "$api_key" ] || [ -n "$api_key_id" ] || [ -n "$api_issuer" ]; then
    [ -n "$api_key" ] && [ -n "$api_key_id" ] && [ -n "$api_issuer" ] \
      || die "API key auth requires --api-key, --api-key-id, and --api-issuer."
    [ -f "$api_key" ] || die "API key file not found: $api_key"
    auth_count=$((auth_count + 1))
    auth_args=(--key "$api_key" --key-id "$api_key_id" --issuer "$api_issuer")
  fi
  if [ -n "$apple_id" ] || [ -n "$apple_password" ] || [ -n "$team_id" ]; then
    [ -n "$apple_id" ] && [ -n "$apple_password" ] && [ -n "$team_id" ] \
      || die "Apple ID auth requires --apple-id, --apple-password, and --team-id."
    auth_count=$((auth_count + 1))
    auth_args=(--apple-id "$apple_id" --password "$apple_password" --team-id "$team_id")
  fi

  [ "$auth_count" -eq 1 ] || die "Specify exactly one notarization auth method (--profile, --api-key*, or --apple-id*)."

  local tmp_dir=""
  local submit_path="$target"
  if [ -d "$target" ] && [[ "$target" == *.app ]]; then
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    submit_path="$tmp_dir/app.zip"
    echo "Archiving $target for notarization..."
    ditto -c -k --keepParent "$target" "$submit_path"
  fi

  echo "Submitting $submit_path to Apple notary service..."
  xcrun notarytool submit "$submit_path" "${auth_args[@]}" --wait

  if [ "$staple" = "true" ] && [[ "$target" != *.zip ]]; then
    echo "Stapling notarization ticket to $target..."
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
  fi
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    exit 1
  fi
  local cmd="$1"
  shift
  case "$cmd" in
    sign-app) cmd_sign_app "$@" ;;
    sign-dmg) cmd_sign_dmg "$@" ;;
    notarize) cmd_notarize "$@" ;;
    -h|--help) usage ;;
    *) die "Unknown subcommand: $cmd" ;;
  esac
}

main "$@"
