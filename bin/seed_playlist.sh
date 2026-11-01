#!/usr/bin/env bash
set -euo pipefail

# seed_playlist.sh NAME FILE [--favourite]
#
# Makes sure my playlist NAME exists and holds every track listed in FILE,
# adding only what is missing, at the end. Unlike the generated playlists it
# never removes anything, so tracks added by hand in Spotify stay.
#
# FILE has one track per line: a spotify:track:<id> URI (anything after it is a
# comment), or "search: Artist | Title", looked up with spotify_player and
# accepted only on an exact artist name and a title starting with Title.
# Blank lines and lines starting with # are ignored.
#
# --favourite flags the playlist in playlist_weights.json as a favourites
# playlist, so its artists earn the favourites points from the next refresh.

root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:?usage: seed_playlist.sh NAME FILE [--favourite]}"
file="${2:?usage: seed_playlist.sh NAME FILE [--favourite]}"
favourite="${3:-}"

# shellcheck source=/dev/null
[ -f "$root/.env" ] && . "$root/.env"
: "${SPOTIFY_USER_ID:?not set — copy .env.example to .env and fill it in}"
# shellcheck source=lib_spotify.sh
. "$root/bin/lib_spotify.sh"

find_playlist() {
  sp get key user-playlists |
    jq -r --arg me "$SPOTIFY_USER_ID" --arg name "$name" \
      '[.[] | select(.owner[1] == $me and .name == $name) | .id] | first // empty'
}

resolve() {
  local line="$1" artist title
  if [[ "$line" =~ ^spotify:track:([A-Za-z0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^search:[[:space:]]*(.+)[[:space:]]*\|[[:space:]]*(.+)$ ]]; then
    artist=$(sed 's/[[:space:]]*$//' <<< "${BASH_REMATCH[1]}")
    title=$(sed 's/[[:space:]]*$//' <<< "${BASH_REMATCH[2]}")
    sp search "$title $artist" | jq -r --arg a "$artist" --arg t "$title" '
      (.tracks | if type == "object" then .items else . end) // []
      | map(select(any(.artists[]; .name == $a)
                   and (.name | ascii_downcase | startswith($t | ascii_downcase))))
      | first.id // empty'
  fi
}

pid=$(find_playlist)
if [ -z "$pid" ]; then
  sp playlist new "$name" "Seeded by spotify_data from $(basename "$file"); add to it freely." >/dev/null
  pid=$(find_playlist)
  [ -n "$pid" ] || { echo "seed: created '$name' but cannot find it" >&2; exit 1; }
  echo "seed: created '$name' ($pid)"
fi

current=$(sp get item -i "$pid" playlist | jq -r '.tracks[].id')
added=0
present=0
missing=0
while IFS= read -r line; do
  line=$(sed 's/^[[:space:]]*//' <<< "$line")
  [ -z "$line" ] || [ "${line:0:1}" = "#" ] && continue
  id=$(resolve "$line")
  if [ -z "$id" ]; then
    echo "seed: no match for '$line'" >&2
    missing=$((missing + 1))
    continue
  fi
  if grep -qx "$id" <<< "$current"; then
    present=$((present + 1))
    continue
  fi
  sp playlist edit add "$pid" --track-id "$id" >/dev/null
  current+=$'\n'"$id"
  added=$((added + 1))
done < "$file"

echo "seed: '$name' $added added, $present already there, $missing not found"

if [ "$favourite" = "--favourite" ]; then
  weights="$root/playlist_weights.json"
  tracks=$(grep -c . <<< "$current" || true)
  jq -S --arg id "$pid" --arg n "$name" --argjson t "$tracks" \
    '.[$id] = ((.[$id] // {weight: 1.0}) + {name: $n, tracks: $t, favourites: true})' \
    "$weights" > "$weights.tmp" && mv "$weights.tmp" "$weights"
  echo "seed: '$name' flagged as a favourites playlist in playlist_weights.json"
fi
