#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/discover_artists.md"
limit="${DISCOVER_LIMIT:-150}"

# An artist counts as known if they appear anywhere in my own data, not merely
# in the ranking: the ranking has a floor, and a near-miss is not a discovery.
excluded=$([ -f "$root/discover_exclude.txt" ] &&
  jq -Rn '[inputs | select(startswith("#") | not) | select(length > 0)]' "$root/discover_exclude.txt" ||
  echo '[]')

known=$(jq -s -r '[.[].tracks[].artists[].name]' "$root"/cache/playlists/*.json |
  jq -s --slurpfile f <(jq -Rn '[inputs | select(length > 0)]' "$root/followed_artists.md") \
        --slurpfile l <(jq -Rn '[inputs | capture("^[0-9]+x  (?<n>.*)$") | .n]' "$root/liked_tracks_artists.md") \
        --slurpfile t <(jq -Rn '[inputs | capture("^[0-9]+x  (?<n>.*)$") | .n]' "$root"/top_tracks_artists_*.md) \
        --argjson x "$excluded" \
        'add + $f[0] + $l[0] + $t[0] + $x | unique')

scores=$(tail -n +3 "$root/favourite_artists.md" |
  sed 's/^ *[0-9]* *\([0-9.]*\)  /\1\t/; s/ \{2,\}[0-9].*$//' |
  jq -Rn '[inputs | split("\t") | {key: .[1], value: (.[0] | tonumber)}] | from_entries')

jq -s -r --argjson known "$known" --argjson scores "$scores" --argjson limit "$limit" '
  ($known | map({key: ., value: true}) | from_entries) as $k
  | [.[] | .artist.name as $src | ($scores[$src] // 0) as $w
         | select($w > 0)
         | .related_artists[] | {name: .name, src: $src, w: $w}]
  | map(select($k[.name] | not))
  | group_by(.name)
  | map({name: .[0].name,
         votes: length,
         score: ([.[].w] | add),
         from: ([.[] | {n: .src, w: .w}] | sort_by(-.w) | map(.n))})
  | sort_by(-.score)
  | .[0:$limit]
  | to_entries[]
  | [(.key + 1), (.value.score | round), .value.votes, .value.name,
     (.value.from[0:3] | join(", "))]
  | @tsv' "$root"/cache/artists/*.json |
awk -F'\t' '
  BEGIN { printf "%4s %6s %6s  %-32s %s\n", "#", "score", "votes", "artist", "recommended by"
          printf "%4s %6s %6s  %-32s %s\n", "----", "------", "-----", "--------------------------------", "--------------" }
  { printf "%4d %6d %6d  %-32s %s\n", $1, $2, $3, $4, $5 }' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) candidates -> $out"
