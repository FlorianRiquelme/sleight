# Sleight — agent notes

macOS menu bar app: webcam → Vision hand landmarks → gestures → shortcuts. Swift package, no
dependencies. Commands and config schema live in `README.md`; this file holds what the code and
`--help` cannot tell you.

## Prove it, then say it

Every claim of "works" in this repo rests on one of these recipes. Use the matching one and quote
the result.

- **Action reached the system** — fire the mapping and read state back:
  `osascript -e 'output muted of (get volume settings)'` before and after `--fire fist`;
  `osascript -e 'tell application "Spotify" to player state'` around a spotify action.
  Key combos have no readable state; fire a pair that round-trips (`swipeLeft` then `swipeRight`).
- **Pipeline behaviour** — `swift test`, then `scripts/replay-all.sh` against the fixtures in
  `recordings/`. A misfire fix is done when the offending recording replays clean *and* every other
  fixture still passes.
- **Live detection** — `timeout 10 .build/debug/sleight --no-ui --dry-run -v`. Expect the
  camera line, `hand in frame`, and an fps line near 25–30. Silence after the camera line means
  frames are not arriving.
- **UI renders** — `scripts/debug-screenshot.sh out.png` captures the debug window; Read the PNG.
- **App stays alive** — background it, sleep 8, `kill -0 $PID`.

## Gotchas that already cost time

- `Camera` must be held by a strong reference. A local `let cam` deallocates when the function
  returns, the session stops, and you get the camera line with no frames ever.
- Vision coordinates: origin bottom-left, normalized 0–1, **not mirrored**. The user's right is
  image-left, so user-rightward motion has negative dx. The debug view mirrors for display only.
- Tests that `import Vision` alongside `@testable import sleight` must write
  `sleight.Joint`; bare `Joint` is ambiguous.
- The executable embeds `Info.plist` via `-sectcreate` so the camera prompt works unbundled. Keep
  `exclude: ["Info.plist"]` in `Package.swift` or SwiftPM warns on every build.
- Permissions attach to the responsible process. Run from a terminal and the terminal owns them;
  run `build/sleight.app` and the app owns them. Missing Accessibility swallows key events
  silently; `ensureAccessibility()` prompts once.
- Tests derive frame counts from `config.holdFrames`; a hardcoded `for i in 0..<10` silently stops
  firing when the default hold changes.
- `swift-tools-version:5.9` on purpose: Swift 5 language mode keeps AppKit/AVFoundation callbacks
  free of strict-concurrency churn.

## Where things live

- All gesture thresholds: `Sources/sleight/GestureClassifier.swift` (static) and
  `Sources/sleight/Swipe.swift` (motion). Nowhere else.
- `Pipeline` is camera-free and driven by frame timestamps, which is what makes replay
  deterministic. Anything that needs wall-clock time belongs in `Engine`, not `Pipeline`.
- `Engine` owns the camera, Vision, recording, and debug output. `StatusBar` and `DebugWindow`
  only observe it.

## Working here

- Changing an approach (classifier strategy, action transport, direction convention)? Read
  `docs/decisions.md` first and append the new decision with its trade-off.
- Shipping a user-visible change? Add a line under `## Unreleased` in `CHANGELOG.md` in the same
  commit.
- A gesture misfires or misses? Follow `docs/debugging.md`. It ends with a labeled recording
  committed to `recordings/`, so the bug cannot return unnoticed.
- Remote: `origin` → github.com/FlorianRiquelme/sleight. The backlog is its issue tracker (`gh issue`);
  file follow-ups there, not in a TODO file. Commit on `feat/…` branches.
- The external webcam has never enumerated on this machine (not in `--list`, not in the USB tree).
  Treat "camera not found" as hardware until proven otherwise.
