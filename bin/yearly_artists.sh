#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/yearly"
out="$root/yearly_artists.md"
json="$root/yearly_artists.json"
weights_file="$root/weights.json"

force=0
if [ "${1:-}" = "--force" ]; then
  force=1
elif [ -n "${1:-}" ]; then
  echo "usage: $(basename "$0") [--force]" >&2
  exit 64
fi

half_life=$(jq -r '.tuning.yearly_half_life_years' "$weights_file")

mkdir -p "$cache"

# Spotify mints one of these per account per year, so they are found by name rather
# than by stored id: a year saved later appears on its own, and no personal id is kept.
wraps=$(spotify_player get key user-playlists |
  jq '[.[] | select(.owner[1] == "spotify")
           | (.name | capture("^Your Top Songs (?<y>[0-9]{4})$") | .y) as $y
           | {year: $y, id, snapshot_id}]
      | sort_by(.year)')

years=$(jq -r '.[].year' <<< "$wraps" | sort)

fetched=0
reused=0
while IFS=$'\t' read -r year id snapshot; do
  file="$cache/$year.json"
  cached=$(jq -r '.playlist.snapshot_id // empty' "$file" 2>/dev/null || true)
  if [ "$force" -eq 0 ] && [ "$cached" = "$snapshot" ]; then
    reused=$((reused + 1))
    continue
  fi
  # Stage then move: an interrupted fetch must not leave a file that later passes the snapshot check.
  spotify_player get item -i "$id" playlist |
    jq --argjson y "$year" '. + {year: $y} | del(.playlist.owner, .playlist.owner_id)' > "$file.tmp"
  mv "$file.tmp" "$file"
  fetched=$((fetched + 1))
done < <(jq -r '.[] | [.year, .id, .snapshot_id] | @tsv' <<< "$wraps")

pruned=0
for file in "$cache"/*.json; do
  [ -e "$file" ] || continue
  if ! grep -qxF "$(basename "$file" .json)" <<< "$years"; then
    rm "$file"
    pruned=$((pruned + 1))
  fi
done

# A year's weight halves every half_life years, so the most recent wrap counts full
# and a decade-old one is a whisper. Without the decay a long-abandoned favourite
# outvotes what is actually being listened to now.
jq -s --argjson hl "$half_life" '
  (map(.year) | max) as $newest
  | map(.year as $y
        | pow(0.5; (($newest - $y) / $hl)) as $w
        | [.tracks[].artists[].name]
        | group_by(.)
        | map({name: .[0], n: length, year: $y, w: $w}))
  | add
  | group_by(.name)
  | map({key: .[0].name,
         value: {score: (([.[] | .n * .w] | add) * 100 | round / 100),
                 years: (sort_by(-.year) | map("\(.year)x\(.n)") | join(" "))}})
  | from_entries' "$cache"/*.json > "$json"

jq -r 'to_entries
  | sort_by(-.value.score, (.key | ascii_downcase))[]
  | [.value.score, .key, .value.years] | @tsv' "$json" |
awk -F'\t' '
  BEGIN { printf "%7s  %-38s %s\n", "score", "artist", "years"
          printf "%7s  %-38s %s\n", "------", "--------------------------------------", "-----------------------------------" }
  { printf "%7.2f  %-38s %s\n", $1, $2, $3 }
' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) artists -> $out"
echo "wraps: $fetched fetched, $reused cached, $pruned pruned"
jq -r --argjson hl "$half_life" '
  (map(.year | tonumber) | max) as $newest
  | "weights (half-life \($hl)y): "
    + ([.[] | "\(.year)=\((pow(0.5; (($newest - (.year | tonumber)) / $hl)) * 100 | round / 100))"]
       | join(" "))' <<< "$wraps"
