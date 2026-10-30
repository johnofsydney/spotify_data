#!/usr/bin/env bash
set -euo pipefail

root="${DATA_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
out="$root/discover_artists.md"
limit="${DISCOVER_LIMIT:-150}"
forget_years="${DISCOVER_FORGET_YEARS:-3}"
half_life=$(jq -r '.tuning.yearly_half_life_years' "$root/weights.json")

# An artist counts as known if they appear anywhere in my own data, not merely
# in the ranking: the ranking has a floor, and a near-miss is not a discovery.
#
# The yearly wraps count too, but they fade. Playing someone enough to chart
# does not mean remembering them a decade later, and a forgotten artist is worth
# rediscovering. The wrap score is already decay-weighted, so an artist stays
# known while it is above what one track scores forget_years back: a one-off
# is forgotten after three years, a heavy rotation takes much longer.
#
# The all-time playlist is deliberately not used here: it carries no dates, so
# nothing in it could ever be forgotten.
#
# Read from the export rather than the cache, as the other sources are, so that
# backtest_discovery.sh can hold artists out by stripping the same file.
played=$([ -f "$root/yearly_artists.json" ] &&
  jq -c --argjson fy "$forget_years" --argjson hl "$half_life" '
    # Wrap scores are rounded to two places, so the floor is too; strictly above
    # it means a one-off is forgotten at exactly forget_years, not a year later.
    (pow(0.5; $fy / $hl) * 100 | round / 100) as $floor
    | to_entries | map(select(.value.score > $floor) | .key)' "$root/yearly_artists.json" ||
  echo '[]')

excluded=$([ -f "$root/discover_exclude.txt" ] &&
  jq -Rn '[inputs | select(startswith("#") | not) | select(length > 0)]' "$root/discover_exclude.txt" ||
  echo '[]')

known=$(jq -s -r '[.[].tracks[].artists[].name]' "$root"/cache/playlists/*.json |
  jq -s --slurpfile f <(jq -Rn '[inputs | select(length > 0)]' "$root/followed_artists.md") \
        --slurpfile l <(jq -Rn '[inputs | capture("^[0-9]+x  (?<n>.*)$") | .n]' "$root/liked_tracks_artists.md") \
        --slurpfile t <(jq -Rn '[inputs | capture("^[0-9]+x  (?<n>.*)$") | .n]' "$root"/top_tracks_artists_*.md) \
        --argjson x "$excluded" \
        --argjson p "$played" \
        'add + $f[0] + $l[0] + $t[0] + $x + $p | unique')

scores=$(jq '[.artists[] | {key: .name, value: .score}] | from_entries' "$root/favourite_artists.json")

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
  | to_entries
  | map({rank: (.key + 1), score: (.value.score | round), votes: .value.votes,
         name: .value.name, from: .value.from[0:3]})' "$root"/cache/artists/*.json > "$root/discover_artists.json"

jq -r '.[] | [.rank, .score, .votes, .name, (.from | join(", "))] | @tsv' "$root/discover_artists.json" |
awk -F'\t' '
  BEGIN { printf "%4s %6s %6s  %-32s %s\n", "#", "score", "votes", "artist", "recommended by"
          printf "%4s %6s %6s  %-32s %s\n", "----", "------", "-----", "--------------------------------", "--------------" }
  { printf "%4d %6d %6d  %-32s %s\n", $1, $2, $3, $4, $5 }' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) candidates -> $out"
