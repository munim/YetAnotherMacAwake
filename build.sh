#!/bin/bash
# Build YetAnotherMacAwake into a standalone .app bundle.
# Usage: ./build.sh [VERSION] [native|universal]
#   VERSION   defaults to 1.0; stamped into CFBundleShortVersionString / CFBundleVersion
#   MODE      native (default) or universal (arm64 + x86_64)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="YetAnotherMacAwake"
APP="$APP_NAME.app"
VERSION="${1:-1.0}"
MODE="${2:-native}"

if [ "$MODE" = "universal" ]; then
    # Cross-compile a fat binary in one pass (SDK ships both slices).
    swift build -c release --arch arm64 --arch x86_64
    BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
    # Plain branch instead of "${ARCH_ARGS[@]}" — macOS bash 3.2 + set -u
    # treats an empty array expansion as an unbound variable.
    swift build -c release
    BIN_DIR=$(swift build -c release --show-bin-path)
fi
# --show-bin-path: multi-arch builds land outside .build/release (xcbuild
# pipeline), so ask SPM for the real output dir instead of hardcoding one.
BIN="$BIN_DIR/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Stamp version BEFORE codesign (codesign seals Info.plist).
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
# Prefer a stable local identity so the Accessibility grant survives rebuilds.
# Create one once with: ./scripts/create-local-cert.sh  (or use a Developer ID).
# Try stable local identity first (cert may not appear as "valid" for codesigning but still works).
STABLE_CN="YetAnotherMacAwake Local"
if security find-certificate -c "$STABLE_CN" -a -p 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
    if codesign --force --sign "$STABLE_CN" --options runtime "$APP" 2>/dev/null; then
        echo "Signed with stable identity: $STABLE_CN (Accessibility grant survives rebuilds)"
    else
        # Fallback: ad-hoc (e.g. keychain locked)
        codesign --force --sign - "$APP"
        echo "NOTE: stable cert found but signing failed (keychain locked?) — fell back to ad-hoc. Run: security unlock-keychain ~/Library/Keychains/login.keychain-db"
    fi
else
    codesign --force --sign - "$APP"
    echo "NOTE: ad-hoc signed — Accessibility grant will be lost on next ./build.sh; re-enable in System Settings > Privacy & Security > Accessibility."
    echo "      Create a stable cert once: ./scripts/create-local-cert.sh"
fi

echo "Built $APP ($VERSION, $MODE)"
