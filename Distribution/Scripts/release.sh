#!/bin/zsh
#
# release.sh — Appshots macOS release pipeline (Developer ID sign + notarize + Sparkle + GitHub Releases).
#
# Consolidates the former Distribution/Scripts/* chain (publish-with-build, workspace_archive,
# sign-release-app, publish-submit-notary, common_package, publish-submit-r2, the config/
# version/shell helpers) into one script. Styled-DMG layout is still delegated to create-dmg.mjs.
#
# Phases:
#   release.sh build    archive → sign (in place) → styled DMG → notarize → staple → package
#                       → also Developer-ID-sign + notarize the standalone appshotsctl CLI into
#                       artifacts/appshotsctl-<version>-arm64.zip; emits version to $GITHUB_OUTPUT
#   release.sh upload   generate Sparkle appcast → attach the immutable DMG + appcast (and the
#                       standalone CLI zip) as assets on the version's GitHub Release
#   release.sh all      build then upload (local one-shot)
#
# The GitHub Actions workflow runs `build`, creates the GitHub Release, then runs `upload`
# (so the published build number — which is read back from the live appcast — advances exactly once).
#
# Signing identity + notary credentials are read from the keychain that the workflow restores
# to Distribution/Keychain/Developer-ID-Keychain.keychain; the Sparkle EdDSA private key from
# Distribution/Keychain/SparkleKeys/private-key.txt.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
KEYCHAIN_DIR="$SCRIPT_DIR/../Keychain"
KEYCHAIN_DB="$KEYCHAIN_DIR/Developer-ID-Keychain.keychain"
SPARKLE_PRIVATE_KEY_PATH="$KEYCHAIN_DIR/SparkleKeys/private-key.txt"
VERSION_XCCONFIG="$PROJECT_ROOT/Sources/Appshots/Configuration/Version.xcconfig"

PROJECT="Appshots.xcodeproj"
SCHEME="Appshots"
BUNDLE_ID="ceo.nerd.appshots"
BUILD_DIR="$PROJECT_ROOT/.build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
DERIVED_DATA="$BUILD_DIR/DerivedData"
XCODEBUILD_LOG="$PROJECT_ROOT/xcodebuild.log"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
DMG_OUTPUT="$BUILD_DIR/Appshots.dmg"
ARTIFACT_DMG="$PROJECT_ROOT/artifacts/Appshots.dmg"

# Standalone signed CLI (appshotsctl) distribution — for GUI-less / Homebrew /
# plugin users who install only the CLI with its own stable TCC identity.
CLI_NAME="appshotsctl"
CLI_BUNDLE_ID="ceo.nerd.appshots.cli"
CLI_ARCH="arm64"
CLI_ENTITLEMENTS="$PROJECT_ROOT/appshotsctl.entitlements"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
# Set APPSHOTS_CLI_DIST=0 to skip the standalone-CLI phase entirely.
APPSHOTS_CLI_DIST="${APPSHOTS_CLI_DIST:-1}"

# Updates are GitHub Release assets. The appcast is attached to every release,
# and Sparkle reads the stable alias below — GitHub redirects it to the newest
# release's copy, so the feed URL baked into shipped builds never changes.
GITHUB_REPO="${APPSHOTS_GITHUB_REPO:-Shahfarzane/appshots}"
SPARKLE_FEED_URL_DEFAULT="https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml"

# ----------------------------------------------------------------------------- logging / paths
log_info() { echo "[i] $*"; }
log_step() { echo "[*] $*"; }
log_ok()   { echo "[+] $*"; }
log_err()  { echo "[-] $*"; }
die()      { log_err "$1"; exit "${2:-1}"; }
require_cmd()  { command -v "$1" > /dev/null 2>&1 || die "$1 required"; }
require_file() { [[ -f "$1" ]] || die "$2"; }

ensure_path() {
  case ":${PATH-}:" in *":/usr/bin:"*) ;; *) PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH-}" ;; esac
  case ":${PATH-}:" in *":/opt/homebrew/bin:"*) ;; *) PATH="/opt/homebrew/bin:${PATH-}" ;; esac
  case ":${PATH-}:" in *":/usr/local/bin:"*) ;; *) PATH="/usr/local/bin:${PATH-}" ;; esac
  export PATH
}

# ----------------------------------------------------------------------------- version parsing
sanitize_version() {
  echo "$1" | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' ' |
    grep -oE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?' || echo "1.0.0"
}
sanitize_build_number() {
  echo "$1" | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' ' |
    grep -oE '^[0-9]+' || echo "1"
}
parse_xcconfig() {
  grep "^$1" "$2" 2> /dev/null | sed 's/.*= *//' | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' \n\r'
}
read_project_version() { sanitize_build_number "$(parse_xcconfig CURRENT_PROJECT_VERSION "$1")"; }

load_project_info() {
  require_file "$VERSION_XCCONFIG" "Version.xcconfig not found: $VERSION_XCCONFIG"
  MARKETING_VERSION=$(sanitize_version "$(parse_xcconfig MARKETING_VERSION "$VERSION_XCCONFIG")")
  PROJECT_VERSION=$(sanitize_build_number "$(parse_xcconfig CURRENT_PROJECT_VERSION "$VERSION_XCCONFIG")")
  [[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || die "invalid version: $MARKETING_VERSION"
  [[ "$PROJECT_VERSION" =~ ^[0-9]+$ ]] || die "invalid build number: $PROJECT_VERSION"
  export MARKETING_VERSION PROJECT_VERSION
  log_ok "project: v$MARKETING_VERSION ($PROJECT_VERSION)"
}

# ----------------------------------------------------------------------------- keychain / identity
unlock_keychain() {
  require_file "$KEYCHAIN_DB" "keychain not found: $KEYCHAIN_DB"
  [[ -n "${KEYCHAIN_PASSWORD:-}" ]] || die "KEYCHAIN_PASSWORD not set"
  KEYCHAIN_DB=$(realpath "$KEYCHAIN_DB")

  local contents id_line
  contents=$(security find-identity -v -p codesigning "$KEYCHAIN_DB")
  id_line=$(echo "$contents" | grep "Developer ID Application" | head -n 1)
  # CODE_SIGN_IDENTITY is the SHA-1 hash (column 2), which is unambiguous if several certs match.
  CODE_SIGNING_IDENTITY=$(echo "$id_line" | awk '{print $2}')
  CODE_SIGNING_TEAM=$(echo "$id_line" | sed 's/.*(\(.*\)).*/\1/')
  [[ -n "$CODE_SIGNING_IDENTITY" ]] || die "cannot find Developer ID Application identity in keychain"
  [[ -n "$CODE_SIGNING_TEAM" ]] || die "cannot find Team ID from Developer ID Application identity"

  # The notarytool credentials are stored inside the same keychain; discover the saved-creds profile name.
  NOTARIZE_KEYCHAIN_PROFILE=$(
    security dump-keychain -r "$KEYCHAIN_DB" | strings |
      grep "com.apple.gke.notary.tool.saved-creds" | head -n 1 | awk -F. '{print $NF}' | tr -d '"'
  )
  [[ -n "$NOTARIZE_KEYCHAIN_PROFILE" ]] || die "cannot find notary profile in keychain"
  log_info "identity=$CODE_SIGNING_IDENTITY team=$CODE_SIGNING_TEAM notary=$NOTARIZE_KEYCHAIN_PROFILE"

  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_DB"
  # Prepend our signing keychain to the user search list while preserving the
  # existing keychains. zsh does NOT word-split unquoted $(...), so the old
  # `... -s "$KEYCHAIN_DB" $current` stored the whole list as one mangled path
  # and corrupted a real user's search list. Parse each path into an array
  # (newline-split via ${(@f)}), drop our own to avoid duplicates, and pass the
  # list quoted.
  local -a existing search_list
  existing=("${(@f)$(security list-keychains -d user | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//')}")
  search_list=("$KEYCHAIN_DB")
  local kc
  for kc in "${existing[@]}"; do
    [[ -n "$kc" && "$kc" != "$KEYCHAIN_DB" ]] && search_list+=("$kc")
  done
  security list-keychains -d user -s "${search_list[@]}"
  security set-keychain-settings -t 3600 -l "$KEYCHAIN_DB"
  export CODE_SIGNING_IDENTITY CODE_SIGNING_TEAM NOTARIZE_KEYCHAIN_PROFILE KEYCHAIN_DB
}

# ----------------------------------------------------------------------------- build number (release-stateful)
latest_published_build() {
  local url="$SPARKLE_FEED_URL_DEFAULT"
  local tmp http_status build
  tmp=$(mktemp)
  for _ in 1 2; do
    http_status=$(curl -sSL -w "%{http_code}" "$url" -o "$tmp" 2> /dev/null || true)
    if [[ "$http_status" == "200" ]]; then
      build=$(awk -F'[<>]' '/<sparkle:version>/{print $3; exit}' "$tmp")
      [[ "$build" =~ ^[0-9]+$ ]] && { rm -f "$tmp"; echo "$build"; return 0; }
    elif [[ "$http_status" == "404" ]]; then
      log_info "no published appcast at $url yet; using 0" >&2
      rm -f "$tmp"; echo "0"; return 0
    fi
    sleep 1
  done
  rm -f "$tmp"
  die "failed to read appcast at $url"
}

increment_build() {
  # Local builds may not want the network round-trip to the published appcast. Setting
  # APPSHOTS_SKIP_BUILD_BUMP=1 keeps the build number in Version.xcconfig as-is and
  # skips the network round-trip. CI leaves this unset, so its behavior is unchanged.
  if [[ "${APPSHOTS_SKIP_BUILD_BUMP:-0}" == "1" ]]; then
    log_info "APPSHOTS_SKIP_BUILD_BUMP=1 — keeping local build number $(read_project_version "$VERSION_XCCONFIG")"
    return 0
  fi
  log_step "auto-incrementing build number..."
  local latest current new
  latest=$(latest_published_build)
  current=$(read_project_version "$VERSION_XCCONFIG")
  [[ "$current" -gt "$latest" ]] 2> /dev/null && latest=$current
  new=$((latest + 1))
  log_info "$current -> $new (latest published: $latest)"
  sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $new/" "$VERSION_XCCONFIG"
  [[ "$(read_project_version "$VERSION_XCCONFIG")" == "$new" ]] || die "build number update failed"
  log_ok "build number updated to $new"
}

# ----------------------------------------------------------------------------- archive + sign
run_xcodebuild() {
  if command -v xcbeautify > /dev/null 2>&1; then
    xcodebuild "$@" 2>&1 | tee "$XCODEBUILD_LOG" | xcbeautify --is-ci --disable-logging --disable-colored-output
  else
    xcodebuild "$@" 2>&1 | tee "$XCODEBUILD_LOG"
  fi
}

archive_app() {
  local feed="${SPARKLE_FEED_URL:-$SPARKLE_FEED_URL_DEFAULT}"
  log_step "archiving $SCHEME v$MARKETING_VERSION ($PROJECT_VERSION) feed=$feed"
  rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA"; rm -f "$XCODEBUILD_LOG"
  mkdir -p "$BUILD_DIR" "$DERIVED_DATA"

  run_xcodebuild \
    -project "$PROJECT_ROOT/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    archive \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$PROJECT_VERSION" \
    SPARKLE_FEED_URL="$feed" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$CODE_SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$CODE_SIGNING_TEAM"

  log_ok "archive generated at $ARCHIVE_PATH"
}

sign_path() {
  local path="$1"; shift
  [[ -e "$path" ]] || { log_info "skipping missing signing path: $path"; return 0; }
  log_step "signing: $path"
  /usr/bin/codesign --force --sign "$CODE_SIGNING_IDENTITY" --timestamp --options runtime "$@" "$path"
}

sign_app() {
  local app="$1"
  [[ -d "$app" ]] || die "app path does not exist: $app"
  [[ -n "${CODE_SIGNING_IDENTITY:-}" ]] || die "CODE_SIGNING_IDENTITY is not set"
  log_step "signing release app with hardened runtime: $app"

  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$sparkle" ]]; then
    sign_path "$sparkle/Versions/B/XPCServices/Installer.xpc"
    sign_path "$sparkle/Versions/B/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
    sign_path "$sparkle/Versions/B/Autoupdate"
    sign_path "$sparkle/Versions/B/Updater.app"
    sign_path "$sparkle"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$sparkle"
  fi

  /usr/bin/codesign --force --deep --sign "$CODE_SIGNING_IDENTITY" \
    --timestamp --options runtime --preserve-metadata=identifier,entitlements "$app"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  log_ok "release app signed"
}

# ----------------------------------------------------------------------------- styled DMG (appdmg)
create_dmg() {
  local app="$1" out="$2"
  [[ -d "$app" && "$app" =~ \.app$ ]] || die "not a .app bundle: $app"
  require_cmd node
  require_file "$PROJECT_ROOT/Resources/Installer/install-bg-app-rect.json" "DMG layout config not found"
  [[ -d "$SCRIPT_DIR/node_modules" ]] || ( cd "$SCRIPT_DIR" && npm install --prefer-offline --no-audit --no-fund )
  rm -f "$out"; mkdir -p "$(dirname "$out")"
  node "$SCRIPT_DIR/create-dmg.mjs" "$app" "$out"
  [[ -f "$out" ]] || die "DMG creation failed"
  log_ok "DMG created: $out ($(du -h "$out" | awk '{print $1}'))"
}

# ----------------------------------------------------------------------------- notarize + staple
notarize_dmg() {
  local app="$1" dmg="$2"
  [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]] || die "NOTARIZE_KEYCHAIN_PROFILE is not set"

  log_step "signing dmg"
  codesign --sign "$CODE_SIGNING_IDENTITY" --timestamp "$dmg" || die "failed to sign dmg"

  log_step "submitting to notary service (profile: $NOTARIZE_KEYCHAIN_PROFILE)"
  set +e
  local out rc
  out=$(xcrun notarytool submit "$dmg" --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" --wait 2>&1)
  rc=$?
  set -e
  echo "$out"

  if [[ "$rc" -ne 0 ]] || ! echo "$out" | grep -q "status: Accepted"; then
    local id
    id=$(echo "$out" | grep "id:" | head -n 1 | awk '{print $2}' || true)
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" || true
    die "notarization failed (exit $rc)"
  fi

  log_step "stapling + validating dmg and app"
  xcrun stapler staple "$dmg"   || die "failed to staple dmg"
  xcrun stapler validate "$dmg" || die "dmg staple validation failed"
  xcrun stapler staple "$app"   || die "failed to staple app"
  xcrun stapler validate "$app" || die "app staple validation failed"
  log_ok "notarized + stapled"
}

# ----------------------------------------------------------------------------- package artifact
package_artifact() {
  local app="$1"
  mkdir -p "$(dirname "$ARTIFACT_DMG")"
  if [[ -f "$DMG_OUTPUT" ]]; then
    log_step "packaging notarized DMG -> $ARTIFACT_DMG"
    cp "$DMG_OUTPUT" "$ARTIFACT_DMG"
  else
    log_step "packaging: building fresh DMG -> $ARTIFACT_DMG"
    create_dmg "$app" "$ARTIFACT_DMG"
  fi
  log_ok "packaged: $ARTIFACT_DMG"
}

# ----------------------------------------------------------------------------- standalone CLI artifact
# Versioned zip name for the standalone appshotsctl binary, e.g.
# appshotsctl-0.1.3-arm64.zip. Lives in $BUILD_DIR (carried between the `build`
# and `upload` phases, like the DMG) and is mirrored into artifacts/.
cli_zip_path() { echo "$BUILD_DIR/${CLI_NAME}-${1}-${CLI_ARCH}.zip"; }

# Locate the appshotsctl binary produced by the release archive. The app embeds
# it at Contents/Helpers/appshotsctl; fall back to the DerivedData products dir.
find_cli_binary() {
  local c
  for c in \
    "$APP_PATH/Contents/Helpers/$CLI_NAME" \
    "$DERIVED_DATA/Build/Products/Release/$CLI_NAME" \
    "$BUILD_DIR/Build/Products/Release/$CLI_NAME"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  local f
  f=$(find "$DERIVED_DATA" -name "$CLI_NAME" -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  return 1
}

# Developer-ID-sign the bare CLI with hardened runtime + its own entitlements,
# stamp its stable identifier, then zip it for notarization/distribution.
# Sets $CLI_ZIP on success. Non-fatal: returns 1 (caller guards) so a missing
# identity / binary never aborts the app release flow.
build_cli_artifact() {
  [[ "$APPSHOTS_CLI_DIST" == "1" ]] || { log_info "standalone CLI dist disabled (APPSHOTS_CLI_DIST=$APPSHOTS_CLI_DIST)"; return 1; }
  [[ -n "${CODE_SIGNING_IDENTITY:-}" ]] || { log_info "no signing identity; skipping standalone CLI artifact"; return 1; }
  require_file "$CLI_ENTITLEMENTS" "CLI entitlements not found: $CLI_ENTITLEMENTS"

  local bin
  bin=$(find_cli_binary) || { log_err "appshotsctl binary not found; skipping standalone CLI artifact"; return 1; }
  log_step "preparing standalone CLI from $bin"

  local stage staged_bin
  stage=$(mktemp -d)
  staged_bin="$stage/$CLI_NAME"
  cp -f "$bin" "$staged_bin"
  chmod +x "$staged_bin"

  log_step "signing standalone CLI (hardened runtime, id=$CLI_BUNDLE_ID)"
  /usr/bin/codesign --force --sign "$CODE_SIGNING_IDENTITY" \
    --timestamp --options runtime \
    --entitlements "$CLI_ENTITLEMENTS" \
    --identifier "$CLI_BUNDLE_ID" \
    "$staged_bin" || { rm -rf "$stage"; die "failed to sign standalone CLI"; }
  /usr/bin/codesign --verify --strict --verbose=2 "$staged_bin" || { rm -rf "$stage"; die "standalone CLI signature verification failed"; }

  CLI_ZIP=$(cli_zip_path "$MARKETING_VERSION")
  rm -f "$CLI_ZIP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staged_bin" "$CLI_ZIP" || { rm -rf "$stage"; die "failed to zip standalone CLI"; }
  rm -rf "$stage"
  log_ok "standalone CLI zipped: $CLI_ZIP ($(du -h "$CLI_ZIP" | awk '{print $1}'))"
  export CLI_ZIP
  return 0
}

# Notarize the CLI zip (notarytool --wait), then attempt to staple. A bare
# Mach-O cannot hold a stapled ticket, so stapling is best-effort: when it is
# unsupported Gatekeeper validates the notarization online instead.
notarize_cli() {
  local zip="$1"
  require_file "$zip" "CLI zip not found: $zip"
  [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]] || die "NOTARIZE_KEYCHAIN_PROFILE is not set"

  log_step "submitting standalone CLI to notary service (profile: $NOTARIZE_KEYCHAIN_PROFILE)"
  set +e
  local out rc
  out=$(xcrun notarytool submit "$zip" --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" --wait 2>&1)
  rc=$?
  set -e
  echo "$out"

  if [[ "$rc" -ne 0 ]] || ! echo "$out" | grep -q "status: Accepted"; then
    local id
    id=$(echo "$out" | grep "id:" | head -n 1 | awk '{print $2}' || true)
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" || true
    die "standalone CLI notarization failed (exit $rc)"
  fi

  if xcrun stapler staple "$zip" > /dev/null 2>&1; then
    xcrun stapler validate "$zip" > /dev/null 2>&1 || true
    log_ok "standalone CLI notarized + stapled"
  else
    log_info "stapler cannot attach a ticket to a bare CLI zip; Gatekeeper validates notarization online"
    log_ok "standalone CLI notarized"
  fi
}

# Build + sign + notarize the CLI and mirror the zip into artifacts/ (so the
# workflow's GitHub-Release step can attach it). Fully guarded: any failure is
# logged and swallowed so the app release flow is never broken.
package_cli_artifact() {
  [[ "$APPSHOTS_CLI_DIST" == "1" ]] || return 0
  if ! build_cli_artifact; then
    log_info "skipping standalone CLI artifact (see above)"
    return 0
  fi
  notarize_cli "$CLI_ZIP"
  mkdir -p "$ARTIFACTS_DIR"
  cp -f "$CLI_ZIP" "$ARTIFACTS_DIR/$(basename "$CLI_ZIP")"
  log_ok "packaged standalone CLI: $ARTIFACTS_DIR/$(basename "$CLI_ZIP")"
}

# ----------------------------------------------------------------------------- emit version (workflow outputs)
emit_version() {
  local plist="$APP_PATH/Contents/Info.plist"
  local v b
  v=$(sanitize_version "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2> /dev/null || echo "1.0.0")")
  b=$(sanitize_build_number "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2> /dev/null || echo "1")")
  log_ok "app: v$v ($b)"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    { echo "number=$v"; echo "tag=v$v"; echo "build=$b"; } >> "$GITHUB_OUTPUT"
  fi
}

# ----------------------------------------------------------------------------- appcast + release upload
find_generate_appcast() {
  local c
  for c in \
    "$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$PROJECT_ROOT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$BUILD_DIR/Build/Products/Release/Sparkle.framework/Versions/B/bin/generate_appcast"; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  command -v generate_appcast > /dev/null 2>&1 && { command -v generate_appcast; return 0; }
  local f
  f=$(find "$BUILD_DIR" -path "*sparkle*bin/generate_appcast" -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  f=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*sparkle*bin/generate_appcast" -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  f=$(find "$PROJECT_ROOT" -name generate_appcast -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$f" ]] && { echo "$f"; return 0; }
  die "generate_appcast not found (build the release first)"
}

# Attaches files as assets on the tag's GitHub Release (creating the release
# for local one-shot runs; CI creates it before the upload phase) and verifies
# each asset landed. Requires an authenticated `gh` (GH_TOKEN in CI).
gh_release_ensure() {
  local tag="$1"
  gh release view "$tag" --repo "$GITHUB_REPO" > /dev/null 2>&1 && return 0
  log_step "creating GitHub release $tag"
  gh release create "$tag" --repo "$GITHUB_REPO" --title "Release $tag" --generate-notes
}

gh_release_put() {
  local tag="$1"; shift
  local f
  gh release upload "$tag" "$@" --repo "$GITHUB_REPO" --clobber
  local assets
  assets=$(gh release view "$tag" --repo "$GITHUB_REPO" --json assets --jq '.assets[].name')
  for f in "$@"; do
    echo "$assets" | grep -qx "$(basename "$f")" || die "release asset missing after upload: $(basename "$f")"
    log_ok "verified release asset: $(basename "$f")"
  done
}

upload_release() {
  local dmg="${1:-$DMG_OUTPUT}"
  require_file "$dmg" "DMG not found: $dmg"
  require_file "$SPARKLE_PRIVATE_KEY_PATH" "Sparkle key not found: $SPARKLE_PRIVATE_KEY_PATH"
  require_cmd shasum; require_cmd hdiutil; require_cmd xcrun; require_cmd gh

  # Detach the DMG mount + remove temp dirs even if a die fires partway through.
  _REL_MOUNT=""; _REL_TMP=""
  _release_cleanup() {
    [[ -n "${_REL_MOUNT:-}" ]] && hdiutil detach "$_REL_MOUNT" -quiet 2> /dev/null || true
    [[ -n "${_REL_MOUNT:-}" && -d "$_REL_MOUNT" ]] && rm -rf "$_REL_MOUNT"
    [[ -n "${_REL_TMP:-}" && -d "$_REL_TMP" ]] && rm -rf "$_REL_TMP"
  }
  trap _release_cleanup EXIT

  # Read the marketing version from the (notarized) DMG.
  local app_in_dmg version
  _REL_MOUNT=$(mktemp -d)
  hdiutil attach "$dmg" -mountpoint "$_REL_MOUNT" -nobrowse -quiet || die "mount failed"
  app_in_dmg=$(find "$_REL_MOUNT" -name "*.app" -maxdepth 1 -type d | head -n 1)
  [[ -n "$app_in_dmg" ]] || die ".app not found in DMG"
  version=$(sanitize_version "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_in_dmg/Contents/Info.plist" 2> /dev/null || echo "1.0.0")")
  hdiutil detach "$_REL_MOUNT" -quiet 2> /dev/null || true; rm -rf "$_REL_MOUNT"; _REL_MOUNT=""
  log_info "version: $version"

  xcrun stapler validate "$dmg" > /dev/null 2>&1 || die "notarization staple invalid"

  local ts sha fname archives
  ts=$(date +%s)
  sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
  fname="${version}-${ts}-${sha}.dmg"
  _REL_TMP=$(mktemp -d); archives="$_REL_TMP/sparkle/archives"; mkdir -p "$archives"
  cp "$dmg" "$archives/$fname"

  local tag="v${version}"
  local gen
  gen=$(find_generate_appcast)
  log_step "generating appcast with $gen"
  # Enclosure URLs point at this release's immutable, versioned asset; the
  # stable feed alias (releases/latest/download/appcast.xml) always redirects
  # to the newest release's appcast.
  ( cd "$_REL_TMP/sparkle" && "$gen" --download-url-prefix "https://github.com/${GITHUB_REPO}/releases/download/${tag}/" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" "$archives" )
  [[ -f "$archives/appcast.xml" ]] || die "appcast.xml not created"

  log_step "publishing Sparkle assets to the $tag GitHub release..."
  gh_release_ensure "$tag"
  gh_release_put "$tag" "$archives/$fname" "$archives/appcast.xml"
  rm -rf "$_REL_TMP"; _REL_TMP=""
  log_ok "published: $fname + appcast.xml -> https://github.com/${GITHUB_REPO}/releases/tag/${tag}"

  upload_cli_artifact "$version"
}

# Attach the standalone CLI zip alongside the DMG/appcast on the same release
# (the Homebrew formula pins its versioned URL). Guarded so a missing zip (CLI
# dist disabled / not built) leaves the app upload flow untouched.
upload_cli_artifact() {
  local version="$1"
  [[ "$APPSHOTS_CLI_DIST" == "1" ]] || { log_info "standalone CLI dist disabled; skipping CLI upload"; return 0; }
  local cli_zip
  cli_zip=$(cli_zip_path "$version")
  if [[ ! -f "$cli_zip" ]]; then
    cli_zip="$ARTIFACTS_DIR/$(basename "$cli_zip")"
  fi
  if [[ ! -f "$cli_zip" ]]; then
    log_info "standalone CLI zip not found for v$version; skipping CLI upload"
    return 0
  fi
  log_step "attaching standalone CLI to the v$version release..."
  gh_release_put "v$version" "$cli_zip"
  log_ok "published standalone CLI: $(basename "$cli_zip")"
}

# ----------------------------------------------------------------------------- phases
cmd_build() {
  ensure_path
  load_project_info
  unlock_keychain
  increment_build
  load_project_info            # re-read so PROJECT_VERSION reflects the bumped build
  archive_app
  sign_app "$APP_PATH"
  mkdir -p "$BUILD_DIR"
  create_dmg "$APP_PATH" "$DMG_OUTPUT"
  notarize_dmg "$APP_PATH" "$DMG_OUTPUT"
  xcrun stapler validate "$DMG_OUTPUT" > /dev/null 2>&1 || die "notarization validation failed"
  package_artifact "$APP_PATH"
  package_cli_artifact
  emit_version
  log_ok "build complete"
}

cmd_upload() { ensure_path; upload_release "${1:-$DMG_OUTPUT}"; }

case "${1:-build}" in
  build)  cmd_build ;;
  upload) shift; cmd_upload "${1:-}" ;;
  all)    cmd_build; cmd_upload ;;
  *)      die "usage: $(basename "$0") {build|upload|all}" ;;
esac
