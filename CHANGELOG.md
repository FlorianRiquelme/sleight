# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). One line per user-visible change, newest
first within a section.

## Unreleased

### Added
- Recording (`--record`, menu toggle) writes JSONL landmarks plus derived state; `replay <file>`
  re-runs a recording against the current or an alternate config and scores against a label.
- Debug window: mirrored preview with finger-state-colored skeleton, palm center, swipe trail, and a
  HUD showing pose, per-finger flags, hold progress, speed, fps, last fired gesture.
- Swipe left/right gestures on palm motion, mapped by default to `ctrl+right` / `ctrl+left`
  (natural direction). Static gestures are gated while the hand moves.
- `spotify` action type via Apple Events; open palm and two fingers default to it.
- `none` action type to disable a gesture; gestures missing from `mappings` fall back to defaults.
- Menu bar app with enable toggle, camera picker, config edit/reload. `scripts/bundle.sh` builds
  `gesturecam.app`.
- JSON config at `~/.config/gesturecam/config.json` with `media`, `key`, `shell` actions.
- Static gestures open palm, fist, two fingers, thumbs up on Vision hand landmarks.

### Fixed
- Swipes never fired: Vision drops the hand mid-motion and the detector reset on every dropout.
- Open palm fired for a hand resting flat on the desk; open-hand poses now need `minOpenExtent`.
- Open palm fired during a swipe wind-up and its cooldown swallowed the swipe; default hold is
  15 frames and the pose a hand settles into after a swipe no longer fires.
- Open palm never fired for a relaxed hand with the thumb alongside the index; the thumb is no
  longer part of the open palm rule.

### Changed
- Cooldown uses frame timestamps instead of wall clock so replays are deterministic.
