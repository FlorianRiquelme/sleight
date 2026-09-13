# Decisions

Append-only. Each entry: what was decided, why, and what would make us revisit it. Newest last.

## 2026-09-13 Swift + Vision, not Python + MediaPipe
Native gives a real menu bar app, on-device landmarks on the Neural Engine, and near-zero CPU for
something that runs all day. Python prototypes faster but needs a bridge for every Mac-side action.
**Revisit if:** we need a gesture MediaPipe detects and Vision does not.

## 2026-09-13 Rule-based finger heuristics, not a trained Core ML classifier
Four static poses are separable by "tip farther from wrist than PIP" plus three thumb tests. Rules
are debuggable frame by frame in the HUD and in `replay -v`; a model is not.
**Revisit if:** labeled recordings show a pose that no threshold separates cleanly, or the gesture
set grows past ~8. The recordings are already the training set.

## 2026-09-13 Open palm is four extended fingers; the thumb is ignored
First labeled fixture (`recordings/openPalm-hold.jsonl`) showed a relaxed palm keeps the thumb
0.26–0.47 hand-widths from the index knuckle, the same range as a fist, so the "thumb clear" test
rejected every one of 284 otherwise-perfect frames. Thumb tests stay for thumbs up, where they
discriminate.
**Revisit if:** a four-fingers-up, thumb-tucked pose is wanted as its own gesture.

## 2026-09-13 Static gestures fire once on hold, never repeat while held
A held pose is one intent. Repeating requires leaving the pose. Cooldown is a second guard against
flicker between two poses.
**Revisit if:** someone wants hold-to-repeat (volume) — that is a new action semantic, not a
threshold change.

## 2026-09-13 Spotify via Apple Events, system media keys as the fallback
Media keys go to whichever app macOS considers the current player; that is often not Spotify.
Apple Events target Spotify by name. `media` stays for mute and volume.
**Revisit if:** Spotify drops AppleScript support or a second player needs the same treatment
(then generalize to a `script` action).

## 2026-09-13 Swipe direction follows the hand ("natural"), in the user's frame
Swipe left → space on the right, matching the trackpad default. Camera frames are not mirrored, so
the detector inverts dx to report the user's direction. Users who disagree swap two config lines.
**Revisit if:** the built-in camera or an external one starts delivering mirrored frames; the sign
in `SwipeDetector.push` is the single place to flip.

## 2026-09-13 Static gestures are gated by palm speed
An open palm mid-swipe would otherwise also fire play/pause. Gating on speed is simpler than
cross-checking gestures against each other.
**Revisit if:** users perform static gestures while walking (speed floor too low), or swipes with
a slow wind-up leak a static fire (raise `stillSpeed` or lengthen `holdFrames`).

## 2026-09-13 Swipe samples survive Vision dropouts
Brisk motion makes Vision lose the hand for 1–8 frames repeatedly; all eight fixture swipes
crossed 0.43–0.58 of the frame yet none fired because the buffer reset on each dropout. Samples
now age out by time only. Vertical tolerance raised to 0.7 (fixtures arc up to 0.5). One of eight
attempts arcs at 0.97 and is deliberately not caught.
**Revisit if:** a hand reappearing elsewhere within the 0.5s window causes phantom swipes.

## 2026-09-13 Open-hand poses are gated on landmark extent (`minOpenExtent` 0.28)
Desk-life fixture: a hand lying flat with fingers spread is geometrically an open palm and fired
twice. Height in frame does not separate (deliberate gestures sit at the same y). Extent does:
desk hands max 0.26, deliberate open palms min 0.31, two fingers 0.33. Closed poses are not gated
(no false positives observed; fist extent is only 0.19). Extent is distance-dependent, so it is a
config knob and shown in the HUD.
**Revisit if:** a user gestures from farther back than ~arm's length, or a fist/thumbs-up false
positive appears in a `none` fixture.

## 2026-09-13 After a swipe, the settling pose is primed, not fired; hold is 15 frames
The open hand that lingers after a swipe is part of the swipe. `GestureStabilizer.prime` marks it
as already fired until the pose changes. Separately, a swipe wind-up pauses ~12 frames with an
open hand, which fired open palm at the old 8-frame hold and its cooldown then swallowed the
swipe; hold is now 15 (~0.5s). Deliberate holds in fixtures last ~2s.
**Revisit if:** 0.5s feels sluggish for media control, in which case gate static fires on a
longer stillness instead of a longer hold.

## 2026-09-13 Recordings are landmarks only, never frames
JSONL of Vision output plus derived state replays deterministically through `Pipeline`, is small,
and contains no imagery, so it can be committed and shared with an agent freely.
**Revisit if:** we need to re-run Vision itself (e.g. a Vision upgrade changes landmarks). Then add
an optional video sidecar; the JSONL stays the contract.

## 2026-09-13 `Pipeline` is driven by frame time, not wall clock
Cooldown and swipe windows use the frame timestamp so a recording replays identically regardless
of machine speed. `Engine` supplies `CACurrentMediaTime()` live and the recorded `t` on replay.
**Revisit if:** never; anything wall-clock belongs in `Engine`.
