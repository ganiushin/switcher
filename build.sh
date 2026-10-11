#!/bin/sh
# Builds build/Switcher.app. Set SIGN_ID to a code signing identity to keep the
# Accessibility permission across rebuilds (ad-hoc signing resets it each time).
set -eu
cd "$(dirname "$0")"

APP=build/Switcher.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target "$(uname -m)-apple-macos13.0" Sources/*.swift -o "$APP/Contents/MacOS/Switcher"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
