#!/bin/zsh
# One command to (re)start sleight.
#   scripts/start.sh          rebuild build/sleight.app and relaunch it in the menu bar
#   scripts/start.sh --dev    debug build, run in the foreground with the debug window and
#                             verbose logs; Ctrl-C quits. Faster compile, no bundle, no login item.
# Config edits never need a rebuild: use "Reload Config" in the menu.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x sleight 2>/dev/null || true
if [[ "${1:-}" == "--dev" ]]; then
  swift build 2>&1 | tail -1
  exec .build/debug/sleight --debug -v
fi
./scripts/bundle.sh
open build/sleight.app
