#!/bin/zsh
# Builds a release binary and wraps it in sleight.app (menu bar only, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | tail -1
APP=build/sleight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/sleight "$APP/Contents/MacOS/sleight"
cp Sources/sleight/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>/dev/null
echo "built $APP  (open with: open $APP)"
