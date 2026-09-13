# gesturecam

Menu bar app that watches your webcam for hand gestures and fires shortcuts.
On-device only (Apple Vision), no frames stored or sent anywhere.

## Gestures

| Gesture | Default action |
|---|---|
| ✋ open palm | Spotify play/pause |
| ✊ fist | media mute |
| ✌️ two fingers | Spotify next track |
| 👍 thumbs up | shell: notification (placeholder, edit it) |
| 👈 swipe left | `ctrl+right` → space to the right |
| 👉 swipe right | `ctrl+left` → space to the left |

Swipe directions are in your frame of reference and follow the trackpad's
"natural" convention: content follows your hand. Swap the two `key` mappings
if you prefer the opposite. Static gestures only fire while the hand is still,
so an open palm mid-swipe doesn't also toggle playback.

A static gesture fires once when held for `holdFrames` frames (~500ms), then needs a
`cooldownSeconds` pause. Repeating the same gesture requires leaving the pose first.
A swipe fires when the palm travels `swipeMinDistance` of the frame width within
`swipeWindowSeconds`, mostly horizontally. `stillSpeed` is the palm speed above
which static gestures are suppressed. Open palm and two fingers also need the hand's landmark
extent to reach `minOpenExtent` of the frame; a hand resting on the desk is smaller and
foreshortened, a hand raised to gesture is not.

## Run

```sh
swift build
.build/debug/gesturecam                 # menu bar app
.build/debug/gesturecam --no-ui -v      # headless, verbose logging for tuning
.build/debug/gesturecam --dry-run       # detect but don't fire actions
.build/debug/gesturecam --debug         # open the debug window at launch
.build/debug/gesturecam --list          # cameras
.build/debug/gesturecam --camera iphone # pick camera by name substring
.build/debug/gesturecam --fire fist     # run one mapping once (test actions)
.build/debug/gesturecam --record out.jsonl --label fist   # record landmarks while you perform a gesture
.build/debug/gesturecam replay out.jsonl [-v] [--config other.json]   # re-run a recording offline
./scripts/bundle.sh                     # build/gesturecam.app
swift test                              # swipe detector tests
```

Needs Camera permission, and Accessibility permission to post key events.

## Debug window

"Debug Window" in the menu (or `--debug`) shows the mirrored camera feed with:

- hand skeleton, green = finger counted as extended, red = curled, yellow = hand moving so static poses are gated
- blue dot = palm center, cyan trail = the swipe detector's sample window
- HUD: current pose and per-finger flags including the three thumb tests, hold progress toward `holdFrames`,
  palm speed vs `stillSpeed` with a swipe distance meter, fps, and the last fired gesture

Frame conversion for the preview only runs while the window is open.

## Recording and replay

A recording is a `.jsonl` file: a header with the camera and config, then one line per frame
with the hand landmarks Vision produced and what the pipeline derived at the time (pose, gating,
speed, hold count, fired gesture). No images. Start one with `--record <file>` and stop with Ctrl-C,
or use "Start Recording" in the menu, which writes to `~/.config/gesturecam/recordings/`.

`replay <file>` runs the recorded landmarks through the current classifier and config and lists
every fire. It marks fires that differ from what happened at record time, so you can change a
threshold and see exactly which misfires disappear or appear. With `--label <gesture>` set at record
time (`none` for "nothing should fire"), replay also reports correct vs. wrong fires and exits non-zero if any are wrong, which makes a
labeled recording usable as a regression test. `-v` prints every frame's finger flags, hold progress,
and speed. `--config` replays against a different config file without touching the live one.

## Config

`~/.config/gesturecam/config.json` is written with defaults on first run.

```json
{
  "camera": "MacBook Pro Camera",
  "holdFrames": 15,
  "cooldownSeconds": 1,
  "swipeMinDistance": 0.25,
  "swipeWindowSeconds": 0.5,
  "stillSpeed": 0.4,
  "minOpenExtent": 0.28,
  "mappings": {
    "openPalm":   { "type": "spotify", "command": "playpause" },
    "fist":       { "type": "key",   "keys": "cmd+shift+m" },
    "twoFingers": { "type": "shell", "command": "open -a Notes" }
  }
}
```

Action types:
- `spotify` — `playpause`, `play`, `pause`, `next`, `previous` (talks to Spotify directly via Apple Events)
- `media` — system media keys, go to whatever app is the current player: `playpause`, `next`, `previous`, `mute`, `volumeup`, `volumedown`, `brightnessup`, `brightnessdown`
- `key` — modifiers `cmd`, `shift`, `alt`, `ctrl`, `fn` plus a key: letters, digits, `space`, `return`, `tab`, `esc`, arrows, `f1`–`f12`, punctuation
- `shell` — run in `/bin/zsh -lc`
- `none` — disable a gesture

Gestures missing from `mappings` get their defaults.

Use "Reload Config" from the menu after editing. Classifier thresholds live in
`Sources/gesturecam/GestureClassifier.swift`.
