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

## 2026-09-13 Closed poses need curled fingers, and a fist keeps its tips inside the palm
The 12-minute idle fixture (`recordings/none-idle-10min.jsonl`) fired fist 15 times, thumbs up 3,
two fingers once: a hand on the mouse or keyboard has no extended finger, so it read as a fist.
"Not extended" (tip ≤ 1.15× the PIP's distance from the wrist) is not "folded". Every deliberate
fist, thumbs up and two-fingers frame folds its closed fingers to 0.41–0.84 of the PIP distance;
resting hands sit at 0.84–1.15. Closed fingers now need `curlRatio` 0.85, the mirror of the 1.15
extension test. A fist additionally keeps every tip within 0.9 palm lengths of the wrist
(fixtures 0.61–0.71): fingers draped over a mouse curl past their PIP too, but from beyond the
knuckles (0.99–1.28). Thumbs up is exempt because the edge-on hand projects its folded fingers
past the knuckles (1.05–1.43).
**Revisit if:** a user's natural fist reads `curl<4` or `tips≥0.9` in `replay -v` / the HUD.

## 2026-09-13 A swipe starts from an open hand; a jump or a handedness flip after a gap is another hand
The idle fixture produced 19 phantom swipes. Vision tracks one hand (`maximumHandCount = 1`) and
with both hands on the desk it alternates between them frame to frame, so the palm center jumps a
quarter of the frame; a palm center averaged from one or two visible joints jitters the same way.
Three guards, each measured against the seven fixture swipes: the palm center needs three of the
five palm joints; the swipe is measured from the oldest sample with ≥3 extended fingers in the
window (real swipes wind up open and lose finger joints only in the fast phase, the desk hands are
closed or half out of frame); and the buffer restarts on a step faster than 6 frame widths/s
(fixture swipes peak at 4.7, hand switches show 6.5–9.2) or when the hand returns from a >0.1s gap
with the other handedness (Vision flips handedness frame to frame during brisk motion, but only a
different hand comes back flipped after a gap). A restarted frame also counts as moving, so the
static hold does not accumulate across two alternating hands.
Cost: one of the three attempts in `swipeLeft-brisk` (t=2.3s) has no frame with countable
fingers and no longer fires; two of three there and four of four in `swipeRight-brisk` remain.
**Revisit if:** users report missed swipes; the first thing to check is whether their swipe frames
show `I1 M1 R1` in `replay -v` before the fast phase. Requiring open fingers at both ends or a
fully located palm at the end was tried and lost every left swipe.

## 2026-09-13 Extent floors: open poses 0.30, closed poses 0.16
Supersedes "closed poses are not gated" above; its revisit condition (a fist false positive in a
`none` fixture) arrived. An open hand held up while talking reaches extent 0.29 (desk hands 0.26,
deliberate open palms 0.33), so `minOpenExtent` moves 0.28 → 0.30. A curled hand on the far side
of the desk passes the finger rules at extent 0.12–0.14 while deliberate fists measure 0.19–0.25,
so fist and thumbs up now need `minClosedExtent` 0.16. Both are config knobs and the HUD prints
both floors on `TOO SMALL`.
**Revisit if:** a user gestures from farther back than arm's length, or the fixtures are
re-recorded at another distance; the margins are ~10% on both floors.

## 2026-09-13 A decision tree on the fixtures did not beat the rules; a personal model stays the long-term aim
`scripts/tree-experiment.py` fits shallow trees on every still frame of the fixtures. On the 16
hand-designed features it rediscovers the same splits (a distance gate, curl on the closed
fingers, an extent cutoff for the fist), needs depth 6 to match the rules, and still drops a
quarter of the thumbs-up frames. On the 42 raw landmarks a depth-3 tree misreads 31 idle frames
against the rules' 58 with near-perfect recall, but it splits on the little-finger knuckle's x
and the thumb tip's height relative to the wrist: the orientation of one user's left hand at one
distance, which is all the positive fixtures contain. Two things it did suggest: palm size
(wrist to middle knuckle) is a finger-independent distance measure that could replace the two
extent floors, and the raw-landmark tree is worth re-running once fixtures vary.
The owner wants a small model trained on their own recordings eventually. The blocker is data
variety, not model capacity.
**Revisit when:** `recordings/` holds right-hand and second-distance fixtures for every gesture
(tracked in the issue backlog). If the raw-landmark tree still generalizes there, ship a personal
model behind the same `Pipeline` interface and keep the rules as the fallback and the explainer.

## 2026-09-13 Static poses need a palm facing the camera; the extent floors drop to one step back
Supersedes "Extent floors: open poses 0.30, closed poses 0.16"; its revisit condition arrived. The
one-step-back fixtures (`recordings/*-far.jsonl`, issue #2) measure fist 0.12, thumbs up 0.20,
open palm 0.21, two fingers 0.23, all under the floors, and the far fist sits inside the idle
fixture's desk hands (0.12–0.16), so no extent floor can admit one and reject the other. Palm
size (wrist to middle knuckle), which the trees had preferred, cannot replace the floors either:
the edge-on far thumbs up has a palm of 0.07, smaller than most desk hands (up to 0.12).
Lowering the floors alone let two open hands from the idle fixture fire (extent 0.22 and 0.27).
What separates them is orientation. Knuckle width over palm length (`span`) is 0.37–0.58 for every
deliberate open palm, fist and two fingers at both distances, and 0.64–0.72 and 1.4 for the two
misfires: a hand seen at an angle foreshortens its palm length, which also invalidates every
size-normalized finger test. Open palm, fist and two fingers now need span ≤ 0.6
(`GestureClassifier.maxPalmSpan`); thumbs up is edge-on by nature (1.3–1.7) and exempt. The floors
move to 0.19 / 0.11, ten percent under the far fixtures; with them at 0 the idle fixture fires once
more, so they stay as a distance limit. The depth-3 tree in `scripts/tree-experiment.py` found the
same split on its own (span ≤ 0.62 for fist, ≤ 0.47 for open palm).
Margins are thin on the fist side: far fists reach span 0.58 at the 98th percentile, the nearest
misfire frame is 0.64. Right-hand fixtures were dropped from #2: the camera on the laptop arm
barely sees that hand, and the `none` fixtures already hold thousands of right-hand frames.
**Revisit if:** a deliberate gesture shows `ANGLED` in `replay -v` or the HUD. Measure that user's
span before widening the gate; 0.6 is one user's hand.

## 2026-09-13 A swipe in the opposite direction within 1.5 s is the hand coming back
`swipeLeft-far` brought the hand back at swipe speed 1.0 s after a swipe and fired swipeRight. One
step back a swipe covers 0.42 of the frame in 0.8 s and the return 0.44 in 1.2 s: the same
kinematics, only the intent differs, so no speed or distance threshold separates them.
`SwipeDetector.returnLockout` ignores the opposite direction for 1.5 s after a swipe. Same-direction
repeats are unaffected (fixture swipes repeat every ~2 s). Cost: a deliberate reverse within 1.5 s
is lost.
**Revisit if:** users report a missed back-swipe; halve the lockout before removing it.

## 2026-09-13 With two distances in the fixtures the rules still win; the tree now agrees with them
Re-run of `scripts/tree-experiment.py` on 7786 idle frames and 2842 gesture frames at both
distances, after the span gate. Per frame, the shipped rules misread 76 idle frames and recall
fist 100%, open palm 95%, thumbs up 100%, two fingers 100%; at the fire level they misfire 0 times
in 12 minutes of idle. The depth-4 tree on the 16 hand features misreads 29 idle frames under
blocked cross-validation at 92–100% recall and rediscovers the rules' structure, span included.
The depth-4 raw-landmark tree misreads 63 at 95–100% recall and still splits on the little-finger
knuckle's x and the thumb tip's x: the orientation of one left hand, now at two distances. A model
would buy a few idle frames per frame and nothing at the fire level, at the price of a classifier
nobody can read in `replay -v`. The rules stay; the tree stays as the check that the feature set
still explains the fixtures.
**Revisit when:** a fixture arrives that the rules cannot pass without a new hand-written feature,
or the set gains another user or hand. Then the tree is the first thing to run, and if it holds,
the personal model goes behind the `Pipeline` interface with the rules as fallback and explainer.

## 2026-09-13 A swipe is not blocked by a static gesture's cooldown
The two wind-up takes for #2 (kept in `~/.config/sleight/recordings/*-windup.jsonl`) paused an
open hand 17 and 33 frames before the stroke; openPalm fired and its 1 s cooldown swallowed the
swipe 0.47 s later. The cooldown exists to stop flicker between two poses; a swipe is a distinct
event with its own suppression window and return lockout in `SwipeDetector`. `Pipeline.fire` now
checks a swipe against the last swipe only; static gestures still cool down after any fire. Both
takes replay with every swipe back and the idle fixture gains no swipe.
The other two options in #3 were measured and not taken. Normalizing `stillSpeed` by palm length:
the far drift stays under 3 palm lengths/s for 20 consecutive frames (hold is 15) while deliberate
holds at arm's length reach 4–5, so the unit does not separate the two. Raising `holdFrames`: the
swipeLeft take is genuinely still (≤ 0.05 frame widths/s) for 33 frames, which no hold under
1.1 s covers, and an open hand held still that long is an open palm by definition
(`recordings/README.md`). The openPalm before a paused wind-up therefore still fires, and the two
takes stay out of `recordings/` because of it.
**Revisit when:** a real-use swipe recording with natural wind-ups exists (#3). If those pause
≥ 15 frames routinely, the pause is the normal case and open palm needs a different trigger than
a hold, not a longer one.

## 2026-09-14 Static poses need an upright hand and fingers no longer than a hand; a swipe restarts on a flip with a jump
First dogfooding day: 4.5 h, hand in frame 39% of the time, 29 fires, 15 wrong, all captured with
"Save Last 20 s As…" and committed as `recordings/*-dogfood-*`. Every static misfire passed the
existing rules honestly: four fingers extended, palm facing the camera (span 0.39–0.56), still for
15 frames, extent above the floor. What separated them from every positive fixture was geometry the
rules did not look at.
- Three were the right hand resting at the image-left edge with the fingers pointing down: middle
  knuckle 0.5–1.0 palm lengths *below* the wrist. Every fixture pose has it ≥ 0.97 above, thumbs up
  (edge-on) ≥ 0.46; a fifth of the idle fixture's hands are knuckle-down. `minUpright` 0.3.
- Four open palms had fingertips 2.1–3.0 palm lengths from the wrist (medians 2.18–2.92 over their
  holds); positives measure median 1.85–2.03, p95 ≤ 2.08. A finger is about one palm long, so the
  palm was foreshortened and the fingers were not: the hand is pitched about its knuckle axis, which
  the span gate (yaw) cannot see. `maxOpenTipReach` 2.1.
- Two fists had tips at 0.81–0.90 palm lengths; fixture fists 0.61–0.77. `fistTipReach` 0.9 → 0.8.
- Five of six swipes were Vision switching to the resting hand or a half-visible one (3–8 joints)
  at the far side of the frame. Their steps were 0.26–0.39 frame widths at 2.6–5.9 fw/s across a
  1–3 frame dropout, under the 6 fw/s teleport guard, and the flip came within the 0.1 s gap the old
  handedness rule required. Inside real swipes Vision does flip handedness, but with steps of
  0.03–0.05. `SwipeDetector.flipJump` 0.15 replaces the gap rule.
Not taken: the sixth swipe misfire is the left hand reaching across the desk from an open pose at
about 1 fw/s (`~/.config/sleight/recordings/none-reach-across-desk.jsonl`). Its palm shrinks by 1.34
over the window as the hand moves away from the camera, but one real swipe shrinks by 1.11 and
others vary by up to 1.96 through foreshortening, so no palm rule separates them on one example.
**Revisit when:** the reach recurs in dogfooding (then a "palm shrinks while moving away" rule has
two examples), or a positive fixture arrives with an open palm above tip reach 2.1.


## 2026-09-15 Fist grabs the front window; a held closed hand tracks through motion; drop snaps to a 3×3 zone grid
Window placement is the first continuous use of the hand (#5). Every earlier gesture was an event;
static poses were even gated on stillness, so "hold a pose while moving" did not exist. The grab
adds it as a mode, not a new pose: the pose mapped to the `window` action (default fist) fires as
before, and from that frame `Pipeline` reports the palm center's displacement every frame until the
hand opens. Any non-open hand keeps the grab, because Vision loosens a fist's joints during motion
and a strict fist test would drop the window mid-move. The swipe detector and the stabilizer are
bypassed while dragging, and the release open hand is primed like the settle after a swipe.
The window moves live through the Accessibility API, which the app already holds for key events,
with a gain of 2 screen widths per frame width so half a frame of hand travel crosses the screen.
The drop does not place the window where the hand left it: palm-center jitter is a few pixels at
frame scale and Vision drops joints in fast motion, so free placement would land a few points off
every time. Instead the window's dragged center picks a cell on a 3×3 grid of the screen it is
over (quarters in the corners, halves on the edges, fill in the middle), which is also the whole
vocabulary Swish offers. A center dragged onto another display snaps on that display. Travel
under 0.05 frame widths restores the original frame, so a fist that fires by accident and opens
again costs nothing. Losing the hand for 0.7 s also restores it: brisk-motion dropouts are 1–8
frames, so 0.7 s means the hand is gone, and the fist fixtures show how that happens: the hand
lowers out of frame after the pose, with 0.17–0.25 of downward travel that would have snapped the
window to the bottom half. Only an open hand commits a drop.
Cost: fist no longer mutes by default; `{"type":"media","key":"mute"}` restores it, and the grab
pose follows whichever static gesture is mapped to `window`.
**Revisit if:** a real drop lands in the wrong cell (measure the dragged center against the grid
before touching the gain), or a fixture shows the hand opening within the first frames of a move
because a loose fist reads as three extended fingers; then the release test needs a hysteresis.
