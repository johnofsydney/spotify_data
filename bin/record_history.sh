#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$root/history/rankings.csv"
depth="${HISTORY_DEPTH:-50}"
today="${HISTORY_DATE:-$(date +%F)}"

# The score only means anything relative to the weights that produced it, so the
# series records them: a change in weights is a discontinuity, not a trend.
weights=$(jq -c -S '.' "$root/weights.json" | shasum -a 256)
weights="${weights:0:8}"

[ -f "$file" ] || echo "date,rank,artist,score,alltime,top,spread,tracks,followed,dedicated,favourite,activity,weights" > "$file"

# Re-running on the same day replaces that day's rows rather than duplicating them.
tmp="$file.tmp"
grep -v "^\"\?$today\"\?," "$file" > "$tmp" || true

jq -r --arg d "$today" --arg w "$weights" --argjson n "$depth" '
  .[0:$n][] | [$d, .rank, .name, .score, .alltime, .top, .spread, .tracks,
               (if .followed then 1 else 0 end), (if .dedicated then 1 else 0 end),
               (if .favourite then 1 else 0 end), (.activity * 100 | round / 100), $w] | @csv' \
  "$root/favourite_artists.json" >> "$tmp"

mv "$tmp" "$file"
rows=$(grep -c "^\"\?$today\"\?," "$file" || true)
echo "history: $rows rows for $today -> $file ($(( $(wc -l < "$file") - 1 )) total)"
