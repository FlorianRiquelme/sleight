# Recordings

Labeled landmark recordings that double as regression fixtures. `scripts/replay-all.sh` replays
every `*.jsonl` here and fails if any labeled fire is wrong.

Naming: `<label>-<what happened>.jsonl`, e.g. `fist-slow-close.jsonl`,
`none-resting-hand-on-desk.jsonl`. The label inside the header is what counts; the filename is for
humans. Label `none` means "nothing should fire".

Contents are Vision landmark coordinates only, no images.

`none-idle-10min.jsonl` (14 MB, 21k frames) is several times the rest of the set combined. It is
12 minutes of typing, mousing, drinking, talking with hands, stretching and standing up, with a
hand in frame two-thirds of the time. Its value is the duration: the static-gesture gates were
tuned on short clips of deliberate gestures, and a daily driver mostly watches a hand that is not
gesturing. It exposed 39 misfires on first replay. Replay takes about a second.
