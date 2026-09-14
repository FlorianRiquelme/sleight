# Recordings

Labeled landmark recordings that double as regression fixtures. `scripts/replay-all.sh` replays
every `*.jsonl` here and fails if any labeled fire is wrong.

Naming: `<label>-<what happened>.jsonl`, e.g. `fist-slow-close.jsonl`,
`none-resting-hand-on-desk.jsonl`. The label inside the header is what counts; the filename is for
humans. Label `none` means "nothing should fire". `*-misfire-*.jsonl` files come from the
"Save Last 20 s As…" menu.

Contents are Vision landmark coordinates only, no images.

`*-hold.jsonl` and `swipe*-brisk.jsonl` are the left hand at arm's length; `*-far.jsonl` the same
hand one step back (extent 0.6 of arm's length). Both distances must pass, so a threshold tuned on
one is caught by the other. A swipe fixture must not hold an open hand still for `holdFrames`
between swipes: that is an open palm by definition and replay will count it as a wrong fire.
Swipe, then drop or close the hand before bringing it back. `scripts/record-fixtures.sh` records
the far set with timed takes.

`swipe*-natural.jsonl` are swipes made the way you swipe while working, with no instruction to
pause or return slowly (#4). Neither take has a single frame classified as openPalm: the hand is
never still and camera-facing before the stroke. The takes that did show a wind-up pause were
"return slowly" instructions and live outside the repo, because they fail as swipe fixtures by
design.

`*-dogfood-<HHMM>-*.jsonl` are "Save Last 20 s As…" captures from the first day of real use
(2026-09-14, 4.5 h). Each `none` file holds one or two wrong fires named in the filename, about
six seconds before the end; the `openPalm` and `swipeLeft` ones are deliberate gestures captured
the same way. Together they cover the right hand resting at the frame edge (fingers down), the left
hand pitched on the desk (fingertips 2.1–3.0 palm lengths out), a relaxed closed hand, and Vision
switching to a second or half-visible hand mid-motion. One capture stayed out: a slow reach across
the desk that fires swipeRight and that no rule separates from a swipe yet.

`none-idle-10min.jsonl` (14 MB, 21k frames) is several times the rest of the set combined. It is
12 minutes of typing, mousing, drinking, talking with hands, stretching and standing up, with a
hand in frame two-thirds of the time. Its value is the duration: the static-gesture gates were
tuned on short clips of deliberate gestures, and a daily driver mostly watches a hand that is not
gesturing. It exposed 39 misfires on first replay. Replay takes about a second.
