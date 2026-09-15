# Changelog

Format: [Keep a Changelog](https://keepachangelog.com). One line per user-visible change, newest
first within a section.

## Unreleased

### Added
- Grab-and-drag window placement (#5): a still fist grabs the frontmost window, the closed hand
  moves it live, and opening the hand drops it into a snap zone on a 3×3 grid of the screen it is
  over (quarters, halves, fill; another display if the window's center is dragged there). A drop
  with almost no travel, or a hand that leaves the frame without opening, restores the original frame. New action type `window`; whichever static
  gesture is mapped to it becomes the grab pose. `--window <zone|print>` snaps or prints the front
  window from the terminal.

### Changed
- Fist is mapped to `window` by default and no longer mutes; map it to `{"type":"media","key":"mute"}`
  to get the old behaviour.
- `replay --csv` gains `dragx,dragy,drop` columns and `replay -v` prints `DRAG`/`DROP` lines.
- `replay --csv` and `replay -v` include fingertip reach (`tips`) and uprightness (`up`).

### Fixed
- First dogfooding day (4.5 h, 29 fires, 15 wrong) turned into 14 fixtures that now replay clean:
  - A hand resting at the frame edge with its fingers pointing down no longer reads as open palm
    or thumbs up: every static pose needs the middle knuckle at least 0.3 palm lengths above the wrist.
  - A hand pitched on the desk, whose fingertips read 2.1–3.0 palm lengths from the wrist, is no
    longer an open palm (`maxOpenTipReach` 2.1; real open palms measure 1.8–2.0).
  - A relaxed closed hand on the desk no longer fires fist: `fistTipReach` 0.9 → 0.8.
  - Vision switching to the other hand, or to a half-visible one, no longer completes a swipe: a
    handedness flip combined with a jump of 0.15 frame widths restarts the motion (real swipes
    flip with steps of 0.03–0.05). The old "flip across a 0.1 s gap" rule is replaced.
- Known: a slow reach across the desk from an open hand still fires a swipe (1 in 4.5 h).

## 0.1.0 - 2026-09-14

### Fixed
- A swipe right after a static gesture is no longer lost to that gesture's cooldown: an open hand
  that pauses before the stroke fires openPalm, and the swipe half a second later now fires too.
  Swipes still cool down after each other. (#3)
- Gestures work from one step back: the extent floors drop to what the far fixtures measure, and
  open palm, fist and two fingers instead require the palm to face the camera (knuckle width over
  palm length ≤ 0.6), which is what kept the idle fixture clean.
- The hand coming back after a swipe no longer fires the opposite swipe: the opposite direction is
  ignored for 1.5 s.
- Stopping a recording with Ctrl-C no longer crashes on a frame that arrives while the file closes.
- Hands resting on the mouse or keyboard no longer fire fist, thumbs up or two fingers: closed
  fingers must fold past their PIP, and a fist keeps its fingertips inside the palm.
- No more phantom swipes when Vision alternates between both hands on the desk: a swipe is measured
  from an open hand, and a jump or a handedness flip after a detection gap restarts the motion.
- A far, curled hand no longer counts as a fist: closed poses have their own extent floor.

### Added
- "Save Last 20 s As…" menu item captures the last 20 seconds seen by the pipeline as a labeled
  `.jsonl` recording, without needing a recording already running.
- Every fire posts a Notification Center banner (config `notifyOnFire`, menu "Notify on Fire") and
  appends a line to `~/.config/sleight/fires.log`, so fires with silent mappings are noticeable and
  reviewable.
- Usage log (`~/.config/sleight/usage.csv`) samples CPU, memory, fps and hand-visibility every
  `--usage-interval` seconds; `scripts/usage-report.sh` summarizes it.

### Changed
- `replay --csv` prints one row per frame of the current pipeline's derived state for offline
  measurement across fixtures; `replay -v` and the CSV include the palm length.
- `minOpenExtent` default 0.28 → 0.30; new config key `minClosedExtent` (0.16) for fist and thumbs up.
- `replay -v` and the HUD show the curled-finger count and fingertip reach; `TOO SMALL` names both floors.

### Added
- `recordings/none-idle-10min.jsonl`: 12 minutes of ordinary desk life labeled `none`, the long
  negative fixture that exposed the misfires above.
- `scripts/start.sh` rebuilds and relaunches the menu bar app in one command; `--dev` runs a debug
  build in the foreground with the debug window and verbose logs.
- Menu bar icon reflects state (running/hand visible/paused/camera problem) and the menu surfaces
  camera and Accessibility problems with "Open … Settings…" shortcuts.
- "Launch at Login" menu toggle via `SMAppService` (only works from `build/sleight.app`).
- Recording (`--record`, menu toggle) writes JSONL landmarks plus derived state; `replay <file>`
  re-runs a recording against the current or an alternate config and scores against a label.
- Debug window: mirrored preview with finger-state-colored skeleton, palm center, swipe trail, and a
  HUD showing pose, per-finger flags, hold progress, speed, fps, last fired gesture.
- Swipe left/right gestures on palm motion, mapped by default to `ctrl+right` / `ctrl+left`
  (natural direction). Static gestures are gated while the hand moves.
- `spotify` action type via Apple Events; open palm and two fingers default to it.
- `none` action type to disable a gesture; gestures missing from `mappings` fall back to defaults.
- Menu bar app with enable toggle, camera picker, config edit/reload. `scripts/bundle.sh` builds
  `sleight.app`.
- JSON config at `~/.config/sleight/config.json` with `media`, `key`, `shell` actions.
- Static gestures open palm, fist, two fingers, thumbs up on Vision hand landmarks.

### Fixed
- Swipes never fired: Vision drops the hand mid-motion and the detector reset on every dropout.
- Open palm fired for a hand resting flat on the desk; open-hand poses now need `minOpenExtent`.
- Open palm fired during a swipe wind-up and its cooldown swallowed the swipe; default hold is
  15 frames and the pose a hand settles into after a swipe no longer fires.
- Open palm never fired for a relaxed hand with the thumb alongside the index; the thumb is no
  longer part of the open palm rule.

### Changed
- Thumbs up defaults to media volume up instead of a placeholder shell notification.
- Cooldown uses frame timestamps instead of wall clock so replays are deterministic.
- The menu bar app now stays running and shows the problem when the camera is missing, denied, or
  errors, instead of exiting (headless `--no-ui` still exits non-zero).
