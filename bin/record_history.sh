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

[ -f "$file" ] || echo "date,rank,artist,score,top,spread,tracks,followed,dedicated,favourite,activity,weights" > "$file"

# Re-running on the same day replaces that day's rows rather than duplicating them.
tmp="$file.tmp"
grep -v "^$today," "$file" > "$tmp" || true

awk -v d="$today" -v w="$weights" -v depth="$depth" '
    NR <= 2 || NR > depth + 2 { next }
    {
      rank = $1; score = $2
      # The artist name runs from column 3 to the first field that starts the
      # numeric block, which is 8 fields from the end.
      name = ""
      for (i = 3; i <= NF - 8; i++) name = name (name == "" ? "" : " ") $i
      gsub(/"/, "\"\"", name)
      printf "%s,%d,\"%s\",%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        d, rank, name, score, $(NF-7), $(NF-5), $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF, w
    }' "$root/favourite_artists.md" >> "$tmp"

mv "$tmp" "$file"
rows=$(grep -c "^$today," "$file" || echo 0)
echo "history: $rows rows for $today -> $file ($(( $(wc -l < "$file") - 1 )) total)"
