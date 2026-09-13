#!/bin/zsh
# Screenshots the gesturecam debug window to $1 (default debug.png).
# Launches the app with --debug --dry-run if no debug window is open, and quits it afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-debug.png}
WAIT=${2:-5}
wid() {
  swift - <<'SWIFT' 2>/dev/null
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowName as String] as? String) == "gesturecam debug" {
    print(w[kCGWindowNumber as String] as! Int); break
}
SWIFT
}
PID=""
W=$(wid)
if [ -z "$W" ]; then
  swift build 2>&1 | grep -E "error" && exit 1
  .build/debug/gesturecam --debug --dry-run >/dev/null 2>&1 &
  PID=$!
  sleep "$WAIT"
  W=$(wid)
fi
[ -n "$W" ] || { echo "no debug window found"; [ -n "$PID" ] && kill $PID; exit 1; }
screencapture -l "$W" -o -x "$OUT"
[ -n "$PID" ] && kill $PID
echo "wrote $OUT"
