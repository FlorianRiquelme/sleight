# Recordings

Labeled landmark recordings that double as regression fixtures. `scripts/replay-all.sh` replays
every `*.jsonl` here and fails if any labeled fire is wrong.

Naming: `<label>-<what happened>.jsonl`, e.g. `fist-slow-close.jsonl`,
`none-resting-hand-on-desk.jsonl`. The label inside the header is what counts; the filename is for
humans. Label `none` means "nothing should fire".

Contents are Vision landmark coordinates only, no images.
