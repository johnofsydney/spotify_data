#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/artists"
ranked="$root/favourite_artists.md"

limit="${1:-200}"
max_age_days="${MAX_AGE_DAYS:-30}"

mkdir -p "$cache"

# Artist IDs come from the playlist cache; fetching by name can match the wrong artist.
ids=$(jq -s -r '[.[].tracks[].artists[] | {name, id}] | unique_by(.name) | INDEX(.name)' \
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
