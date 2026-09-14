#!/bin/zsh
# Summarizes ~/.config/sleight/usage.csv (or $1): overall averages/peaks, plus a per-hour table.
set -uo pipefail
FILE="${1:-$HOME/.config/sleight/usage.csv}"

if [[ ! -f "$FILE" ]]; then
    echo "no such file: $FILE" >&2
    exit 1
fi

awk -F, '
NR == 1 { next }
{
    n++
    cpu_sum += $2; if ($2 > cpu_peak) cpu_peak = $2
    fps_sum += $4
    hand_sum += $5

    hour = substr($1, 1, 13)  # yyyy-MM-ddTHH
    if (!(hour in seen)) { order[++hn] = hour; seen[hour] = 1; batt_start[hour] = $6 }
    batt_end[hour] = $6
    hcpu_sum[hour] += $2; hcpu_n[hour]++
    if ($3 > hrss_max[hour]) hrss_max[hour] = $3
    hhand_sum[hour] += $5
}
END {
    if (n == 0) { print "no data rows"; exit 0 }
    printf "overall: avg cpu %.1f%%  peak cpu %.1f%%  avg fps %.1f  avg hand %.0f%%\n", cpu_sum/n, cpu_peak, fps_sum/n, hand_sum/n
    print ""
    printf "%-15s %8s %10s %9s %12s %10s\n", "hour", "avg_cpu%", "max_rss_mb", "avg_hand%", "batt_start", "batt_end"
    for (i = 1; i <= hn; i++) {
        h = order[i]
        printf "%-15s %8.1f %10d %9.0f %12s %10s\n", h, hcpu_sum[h]/hcpu_n[h], hrss_max[h], hhand_sum[h]/hcpu_n[h], batt_start[h], batt_end[h]
    }
}
' "$FILE"
