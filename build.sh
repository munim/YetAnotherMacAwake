#!/bin/bash
# Build MacAwake.swift into a standalone .app bundle
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacAwake"
APP="$APP_NAME.app"

swift build -c release
BIN=".build/release/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
