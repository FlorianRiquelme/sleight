#!/bin/zsh
# Records the fixtures issue #2 asks for: every static gesture with the right hand and with the
# left hand one step back, plus right-hand swipes. One timed take per file, so you never have to
# touch the keyboard mid-gesture. Takes whose file already exists are skipped; delete a bad take
# and re-run to redo just that one. Actions are dry-run, so nothing fires while you record.
set -uo pipefail
cd "$(dirname "$0")/.."
swift build 2>&1 | grep -E "error" && exit 1
BIN=.build/debug/sleight
HOLD=${HOLD:-20}    # seconds per static take
SWIPE=${SWIPE:-15}  # seconds per swipe take

take() { # <file stem> <label> <seconds> <instruction>
  local file=recordings/$1.jsonl
  [ -e "$file" ] && { echo "skip  $file exists"; return; }
  echo; echo "NEXT ($3s): $4"; echo "      → $file"
  for i in 3 2 1; do echo "      $i"; sleep 1; done
  $BIN --no-ui --dry-run --record "$file" --label "$2" & local pid=$!
  sleep "$3"; kill -TERM $pid 2>/dev/null; wait $pid
  echo "      saved $(($(wc -l < "$file") - 1)) frames"
}

echo "Usual seat, arm's length. RIGHT hand. Hold each gesture ~2s, drop the hand, repeat until told."
take openPalm-right   openPalm   $HOLD "RIGHT hand, arm's length: open palm, fingers spread"
take fist-right       fist       $HOLD "RIGHT hand, arm's length: fist"
take twoFingers-right twoFingers $HOLD "RIGHT hand, arm's length: index + middle up, others folded"
take thumbsUp-right   thumbsUp   $HOLD "RIGHT hand, arm's length: thumbs up"
take swipeLeft-right  swipeLeft  $SWIPE "RIGHT hand, open: swipe toward YOUR LEFT, 3–4 times, return slowly"
take swipeRight-right swipeRight $SWIPE "RIGHT hand, open: swipe toward YOUR RIGHT, 3–4 times, return slowly"

echo; echo "Now move ONE STEP BACK from the camera. LEFT hand, same gestures."
take openPalm-far     openPalm   $HOLD "LEFT hand, one step back: open palm"
take fist-far         fist       $HOLD "LEFT hand, one step back: fist"
take twoFingers-far   twoFingers $HOLD "LEFT hand, one step back: two fingers"
take thumbsUp-far     thumbsUp   $HOLD "LEFT hand, one step back: thumbs up"

echo; echo "All takes done. Next: scripts/replay-all.sh"
