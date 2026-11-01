#!/usr/bin/env bash
set -euo pipefail

# Fetches the full artist payload (top tracks, albums, related artists) for the
# head of the discovery list into cache/discover/. These artists are, by
# definition, not in cache/artists. Both the discovery playlist and the album
# recommendations read it. A month-old copy is fine: an artist's top tracks and
# discography barely move week to week.

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/discover"
artists="${DISCOVER_PLAYLIST_ARTISTS:-${PAGE_DISCOVER:-50}}"
max_age_days="${MAX_AGE_DAYS:-30}"

# shellcheck source=lib_spotify.sh
. "$root/bin/lib_spotify.sh"

mkdir -p "$cache"

fetched=0
reused=0
while read -r id; do
  file="$cache/$id.json"
  if [ -f "$file" ] && [ -z "$(find "$file" -mtime +"$max_age_days")" ]; then
    reused=$((reused + 1))
    continue
  fi
  # Stage then move: an interrupted fetch must not leave a file that looks fresh.
  sp get item -i "$id" artist > "$file.tmp"
  mv "$file.tmp" "$file"
  fetched=$((fetched + 1))
done < <(jq -r --argjson n "$artists" '.[0:$n][].id // empty' "$root/discover_artists.json")

echo "discover artists: $fetched fetched, $reused cached"
