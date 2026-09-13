# Recordings

Labeled landmark recordings that double as regression fixtures. `scripts/replay-all.sh` replays
every `*.jsonl` here and fails if any labeled fire is wrong.

Naming: `<label>-<what happened>.jsonl`, e.g. `fist-slow-close.jsonl`,
`none-resting-hand-on-desk.jsonl`. The label inside the header is what counts; the filename is for
humans. Label `none` means "nothing should fire".

Contents are Vision landmark coordinates only, no images.

`*-hold.jsonl` and `swipe*-brisk.jsonl` are the left hand at arm's length; `*-far.jsonl` the same
hand one step back (extent 0.6 of arm's length). Both distances must pass, so a threshold tuned on
one is caught by the other. A swipe fixture must not hold an open hand still for `holdFrames`
between swipes: that is an open palm by definition and replay will count it as a wrong fire.
Swipe, then drop or close the hand before bringing it back. `scripts/record-fixtures.sh` records
the far set with timed takes.

`none-idle-10min.jsonl` (14 MB, 21k frames) is several times the rest of the set combined. It is
12 minutes of typing, mousing, drinking, talking with hands, stretching and standing up, with a
hand in frame two-thirds of the time. Its value is the duration: the static-gesture gates were
tuned on short clips of deliberate gestures, and a daily driver mostly watches a hand that is not
gesturing. It exposed 39 misfires on first replay. Replay takes about a second.
