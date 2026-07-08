#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
VERSION_XCCONFIG="$ROOT_DIR/Sources/Appshots/Configuration/Version.xcconfig"
MARKETING_VERSION="$(grep '^MARKETING_VERSION' "$VERSION_XCCONFIG" | sed 's/.*= *//' | tr -d '[:space:]')"
CURRENT_PROJECT_VERSION="$(grep '^CURRENT_PROJECT_VERSION' "$VERSION_XCCONFIG" | sed 's/.*= *//' | tr -d '[:space:]')"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/Shahfarzane/appshots/releases/latest/download/appcast.xml}"

swift build --package-path "$ROOT_DIR" -c "$CONFIG" --product Appshots
swift build --package-path "$ROOT_DIR" -c "$CONFIG" --product appshotsctl
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIG" --product Appshots --show-bin-path)"

APP_DIR="$ROOT_DIR/.build/Appshots.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$HELPERS_DIR"

cp "$BIN_DIR/Appshots" "$MACOS_DIR/Appshots"
# Embed the appshotsctl helper so the in-app MCP server points at the bundle, not the repo.
cp "$BIN_DIR/appshotsctl" "$HELPERS_DIR/appshotsctl"
chmod +x "$HELPERS_DIR/appshotsctl"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
find "$BIN_DIR" -maxdepth 1 \( -name "appshots_AppshotsCore.resources" -o -name "appshots_AppshotsCore.bundle" \) -exec cp -R {} "$RESOURCES_DIR/" \;
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [[ -f "$ROOT_DIR/Resources/Appshot.wav" ]]; then
    cp "$ROOT_DIR/Resources/Appshot.wav" "$RESOURCES_DIR/Appshot.wav"
fi
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -path "*/Sparkle.framework" -type d -print -quit 2>/dev/null || true)"
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
fi
chmod +x "$MACOS_DIR/Appshots"

# Ensure the executable can find the embedded Sparkle.framework at runtime.
if ! otool -l "$MACOS_DIR/Appshots" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/Appshots"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Appshots" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ceo.nerd.appshots" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Appshots" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CURRENT_PROJECT_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$CONTENTS_DIR/Info.plist"

# install_name_tool + PlistBuddy invalidate any prior signature, so re-sign.
#
# macOS keys TCC grants — Screen Recording especially — to the app's code
# signature. An ad-hoc signature is not a stable, trusted identity, so the
# grant is re-prompted on every launch and never persists across a quit +
# reopen. Sign with the Developer ID Application identity when it is available
# (TCC keys it on Team ID + bundle ID, so the grant survives restarts *and*
# future rebuilds); fall back to ad-hoc only when no identity is present.
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="-"
    echo "warning: no Developer ID Application identity in the keychain — ad-hoc" \
         "signing; the Screen Recording grant will NOT persist across restarts" >&2
fi

sign() { codesign --force --sign "$SIGN_IDENTITY" "$@"; }

# Inside-out: nested code must be validly signed before the outer app seals
# over it, or `codesign --verify --deep` fails. Preserve the Sparkle XPC
# services' own entitlements so auto-update keeps working.
SPARKLE_BUNDLE="$FRAMEWORKS_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_BUNDLE" ]]; then
    [[ -e "$SPARKLE_BUNDLE/Versions/B/XPCServices/Installer.xpc" ]] \
        && sign --preserve-metadata=entitlements "$SPARKLE_BUNDLE/Versions/B/XPCServices/Installer.xpc"
    [[ -e "$SPARKLE_BUNDLE/Versions/B/XPCServices/Downloader.xpc" ]] \
        && sign --preserve-metadata=entitlements "$SPARKLE_BUNDLE/Versions/B/XPCServices/Downloader.xpc"
    [[ -e "$SPARKLE_BUNDLE/Versions/B/Autoupdate" ]] && sign "$SPARKLE_BUNDLE/Versions/B/Autoupdate"
    [[ -e "$SPARKLE_BUNDLE/Versions/B/Updater.app" ]] && sign "$SPARKLE_BUNDLE/Versions/B/Updater.app"
    sign "$SPARKLE_BUNDLE"
fi
sign "$HELPERS_DIR/appshotsctl"
sign "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1 \
    || echo "warning: code signature verification failed for $APP_DIR" >&2

echo "$APP_DIR"
