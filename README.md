# gesturecam

Menu bar app that watches your webcam for hand gestures and fires shortcuts.
On-device only (Apple Vision), no frames stored or sent anywhere.

## Gestures

| Gesture | Default action |
|---|---|
| ✋ open palm | media play/pause |
| ✊ fist | media mute |
| ✌️ two fingers | media next track |
| 👍 thumbs up | shell: notification (placeholder, edit it) |

A gesture fires once when held for `holdFrames` frames (~250ms), then needs a
`cooldownSeconds` pause. Repeating the same gesture requires leaving the pose first.

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
```

Needs Camera permission, and Accessibility permission to post key events.

## Config

`~/.config/gesturecam/config.json` is written with defaults on first run.

```json
{
  "camera": "MacBook Pro Camera",
  "holdFrames": 8,
  "cooldownSeconds": 1,
  "mappings": {
    "openPalm":   { "type": "media", "key": "playpause" },
    "fist":       { "type": "key",   "keys": "cmd+shift+m" },
    "twoFingers": { "type": "shell", "command": "open -a Notes" }
  }
}
```

Action types:
- `media` — `playpause`, `next`, `previous`, `mute`, `volumeup`, `volumedown`, `brightnessup`, `brightnessdown`
- `key` — modifiers `cmd`, `shift`, `alt`, `ctrl`, `fn` plus a key: letters, digits, `space`, `return`, `tab`, `esc`, arrows, `f1`–`f12`, punctuation
- `shell` — run in `/bin/zsh -lc`

Use "Reload Config" from the menu after editing. Classifier thresholds live in
`Sources/gesturecam/GestureClassifier.swift`.
