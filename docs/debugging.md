# Debugging a misfire or a miss

Goal: turn "it sometimes triggers when I rest my hand" into a committed fixture that replays clean.

1. **Capture it.** The human records the offending motion with the intended gesture as label:
   ```sh
   .build/debug/sleight --no-ui --dry-run --record recordings/thumbsUp-resting-hand.jsonl --label thumbsUp
   ```
   Ctrl-C after a few repetitions. For a false positive with no intended gesture, use `--label none`.
   → done when the file has a header line and a few hundred frames (`wc -l`).

2. **Reproduce offline.**
   ```sh
   .build/debug/sleight replay recordings/<file>.jsonl
   ```
   → done when the replay shows the same wrong fire the human saw. If it does not, the problem is
   upstream of `Pipeline` (camera, Vision, permissions) and replay cannot help; go to the live
   recipe in `CLAUDE.md`.

3. **Find the flipping test.** `replay <file> -v` prints per frame:
   `pose=… I1 M1 R0 L0 curl=2 tips=1.12 T1(s1 c1 u0) ext=0.31 palm=0.16 span=0.45 hold=5/15 speed=0.03`. Read the
   frames just before the fire. Each flag maps to one rule in `GestureClassifier.features`
   (I/M/R/L = finger extended, curl = fingers folded past their PIP, tips = farthest fingertip in
   palm lengths, T = thumb, s/c/u = straight/clear/up, ext = extent, palm = wrist-to-knuckle length
   as a fraction of the frame, span = knuckle width in palm lengths; `SMALL` or `ANGLED` after it
   names the gate that refused the pose). The flag that
   disagrees with reality names the threshold.
   → done when you can say which single comparison is wrong and by roughly how much.

4. **Change one threshold.** Edit it in `GestureClassifier.swift` or `Swipe.swift`. Rebuild.
   Replay with `[new vs. recording]` / `no longer fire` lines as the diff.
   → done when the offending fire is gone and no `[new vs. recording]` fire appeared.

5. **Check every fixture.** `scripts/replay-all.sh`.
   → done when it exits 0. If another fixture broke, the threshold is a trade-off; record it in
   `docs/decisions.md` or find a different rule.

6. **Commit the recording with the fix.** The fixture is the regression test.

## Cheap looks

- `replay <file> --csv > file.csv` — one row per frame of what the current pipeline derives (t,
  hand, pose, gated, speed, palm, extent, span, hold, candidate, fired). Use it for any measurement
  across fixtures, e.g. "what speed unit separates a wind-up from a hold". Never recompute speed or
  palm length outside `Pipeline` to answer such a question, and never read the `d` fields inside a
  recording for it: they are what fired at record time under that day's config and go stale with
  every threshold change (`replay` marks the drift as `[new vs. recording]` / `no longer fire`).

- `scripts/debug-screenshot.sh out.png` — screenshot the live debug window (launches the app with
  `--debug --dry-run` if no window is open). Read the PNG to see skeleton colors and the HUD.
- A synthetic hand for unit tests lives in `Tests/sleightTests/PipelineTests.swift`
  (`hand(index:middle:ring:little:thumbOut:thumbUp:offset:)`). Extend it before reaching for a
  recording when the question is about a rule, not about real landmark noise.
