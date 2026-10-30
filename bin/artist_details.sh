#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/artists"
ranked="$root/favourite_artists.md"

limit="${1:-200}"
max_age_days="${MAX_AGE_DAYS:-30}"

mkdir -p "$cache"

# Artist IDs come from the data, not from a name search, which can match the wrong
# artist. Playlists are the bulk of them; followed artists and top tracks cover the
# ones I follow or play but have never filed in a playlist.
# spotify_player allows one instance at a time, so these run in sequence.
followed_ids=$(spotify_player get key user-followed-artists | jq '[.[] | {name, id}]')
top_ids=$(spotify_player get key user-top-tracks | jq '[.[].artists[] | {name, id}]')

alltime_ids=$([ -f "$root/cache/special/alltime.json" ] &&
  jq '[.tracks[].artists[] | {name, id}]' "$root/cache/special/alltime.json" || echo '[]')
yearly_ids=$(ls "$root"/cache/yearly/*.json >/dev/null 2>&1 &&
  jq -s '[.[].tracks[].artists[] | {name, id}]' "$root"/cache/yearly/*.json || echo '[]')

ids=$(jq -s -r --argjson f "$followed_ids" --argjson t "$top_ids" --argjson a "$alltime_ids" --argjson y "$yearly_ids" \
  '[.[].tracks[].artists[] | {name, id}] + $f + $t + $a + $y | unique_by(.name) | INDEX(.name)' \
  "$root"/cache/playlists/*.json)

fetched=0
reused=0
missing=0
while read -r name; do
  id=$(jq -r --arg n "$name" '.[$n].id // empty' <<< "$ids")
  if [ -z "$id" ]; then
    missing=$((missing + 1))
    continue
  fi
  file="$cache/$id.json"
  if [ -f "$file" ] && [ -z "$(find "$file" -mtime +"$max_age_days")" ]; then
    reused=$((reused + 1))
    continue
  fi
  spotify_player get item -i "$id" artist > "$file.tmp"
  mv "$file.tmp" "$file"
  fetched=$((fetched + 1))
done < <(tail -n +3 "$ranked" | head -n "$limit" | sed 's/^ *[0-9]* *[0-9.]*  //; s/ \{2,\}[0-9].*$//')

echo "artists: $fetched fetched, $reused cached, $missing without an id"
