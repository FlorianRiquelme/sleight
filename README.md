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

A static gesture fires once when held for `holdFrames` frames (~250ms), then needs a
`cooldownSeconds` pause. Repeating the same gesture requires leaving the pose first.
A swipe fires when the palm travels `swipeMinDistance` of the frame width within
`swipeWindowSeconds`, mostly horizontally. `stillSpeed` is the palm speed above
which static gestures are suppressed.

## Run

```sh
swift build
.build/debug/gesturecam                 # menu bar app
.build/debug/gesturecam --no-ui -v      # headless, verbose logging for tuning
.build/debug/gesturecam --dry-run       # detect but don't fire actions
.build/debug/gesturecam --list          # cameras
.build/debug/gesturecam --camera iphone # pick camera by name substring
.build/debug/gesturecam --fire fist     # run one mapping once (test actions)
./scripts/bundle.sh                     # build/gesturecam.app
swift test                              # swipe detector tests
```

Needs Camera permission, and Accessibility permission to post key events.

## Config

`~/.config/gesturecam/config.json` is written with defaults on first run.

```json
{
  "camera": "MacBook Pro Camera",
  "holdFrames": 8,
  "cooldownSeconds": 1,
  "swipeMinDistance": 0.25,
  "swipeWindowSeconds": 0.5,
  "stillSpeed": 0.4,
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
