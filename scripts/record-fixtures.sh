#!/bin/zsh
# Records the second-distance fixtures for issue #2: every gesture with the left hand one step
# back from the camera. (Right-hand takes were dropped: the laptop-arm camera barely sees that
# hand, and the none fixtures already cover it.) One timed take per file, so you never have to
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

echo "Usual seat, then ONE STEP BACK from the camera. LEFT hand. Hold each gesture ~2s, drop the hand, repeat until told."
take openPalm-far     openPalm   $HOLD "LEFT hand, one step back: open palm, fingers spread"
take fist-far         fist       $HOLD "LEFT hand, one step back: fist"
take twoFingers-far   twoFingers $HOLD "LEFT hand, one step back: index + middle up, others folded"
take thumbsUp-far     thumbsUp   $HOLD "LEFT hand, one step back: thumbs up"
echo; echo "Swipes: never hold an open hand still (that is an open palm). Swipe, close or drop the hand, bring it back, swipe again."
take swipeLeft-far    swipeLeft  $SWIPE "LEFT hand, open, one step back: swipe toward YOUR LEFT, 3–4 times"
take swipeRight-far   swipeRight $SWIPE "LEFT hand, open, one step back: swipe toward YOUR RIGHT, 3–4 times"

echo; echo "All takes done. Next: scripts/replay-all.sh"
