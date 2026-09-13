#!/bin/zsh
# Replays every labeled recording; exits non-zero if any fixture has a wrong fire.
set -uo pipefail
cd "$(dirname "$0")/.."
swift build 2>&1 | grep -E "error" && exit 1
BIN=.build/debug/sleight
fail=0; n=0
for f in recordings/*.jsonl(N); do
  n=$((n+1))
  if out=$($BIN replay "$f" "$@" 2>&1); then
    echo "PASS  $f  $(echo "$out" | grep -E '^label' || true)"
  else
    fail=$((fail+1))
    echo "FAIL  $f"; echo "$out" | sed 's/^/      /'
  fi
done
echo "$n fixtures, $fail failed"
[ $fail -eq 0 ]
