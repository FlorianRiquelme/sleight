#!/bin/zsh
# Builds a release binary and wraps it in gesturecam.app (menu bar only, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | tail -1
APP=build/gesturecam.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/gesturecam "$APP/Contents/MacOS/gesturecam"
cp Sources/gesturecam/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>/dev/null
echo "built $APP  (open with: open $APP)"
