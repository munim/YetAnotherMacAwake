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
# Stamp version BEFORE codesign (codesign seals Info.plist).
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP ($VERSION, $MODE)"
