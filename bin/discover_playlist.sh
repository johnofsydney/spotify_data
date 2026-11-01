#!/usr/bin/env bash
set -euo pipefail

# Turns the discovery ranking into a Spotify playlist: the top tracks of the
# artists on the page's "Worth investigating" list, rebuilt in place every run.
#
# The playlist is found by name among my own playlists and created if missing,
# so no id is stored. playlist_artists.sh skips it by the same name: it is
# Spotify-adjacent recommendation, not a choice I made, and caching it would make
# every artist on it "known" and empty the discovery list a week later.

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/discover"

# shellcheck source=/dev/null
[ -f "$root/.env" ] && . "$root/.env"
: "${SPOTIFY_USER_ID:?not set — copy .env.example to .env and fill it in}"

name="${DISCOVER_PLAYLIST_NAME:-Worth Investigating}"
artists="${DISCOVER_PLAYLIST_ARTISTS:-${PAGE_DISCOVER:-50}}"
per_artist="${DISCOVER_PLAYLIST_TRACKS:-2}"
description="Rebuilt weekly by spotify_data: the top ${per_artist} tracks of each artist my favourites point at that I do not have yet."

# Normally already run by refresh.sh, in which case every file is fresh and this
# only checks their dates.
"$root/bin/fetch_discover.sh"

# One track from every artist before a second from any, so the start of the
# playlist is the whole list rather than the top few artists in depth. A track
# shared by two listed artists is kept once, where it first appears.
desired=$(jq -s -r --argjson n "$artists" --argjson per "$per_artist" '
  (.[0][0:$n] | map(.id)) as $order
  | (.[1:] | map({key: .artist.id, value: [.top_tracks[]?.id][0:$per]}) | from_entries) as $top
  | [range(0; $per) as $round | $order[] | $top[.][$round] // empty]
  | reduce .[] as $t ([]; if index($t) then . else . + [$t] end)
  | .[]' "$root/discover_artists.json" "$cache"/*.json)

if [ -z "$desired" ]; then
  echo "playlist: no tracks to add, leaving '$name' alone" >&2
  exit 1
fi

find_playlist() {
  spotify_player get key user-playlists |
    jq -r --arg me "$SPOTIFY_USER_ID" --arg name "$name" \
      '[.[] | select(.owner[1] == $me and .name == $name) | .id] | first // empty'
}

pid=$(find_playlist)
if [ -z "$pid" ]; then
  public_flag=()
  [ "${DISCOVER_PLAYLIST_PUBLIC:-0}" = "1" ] && public_flag=(--public)
  spotify_player playlist new "$name" "$description" ${public_flag[@]+"${public_flag[@]}"} >/dev/null
  pid=$(find_playlist)
  [ -n "$pid" ] || { echo "playlist: created '$name' but cannot find it" >&2; exit 1; }
  echo "playlist: created '$name' ($pid)"
fi

current=$(spotify_player get item -i "$pid" playlist | jq -r '.tracks[].id')

if [ "$current" = "$desired" ]; then
  echo "playlist: '$name' unchanged, $(wc -l <<< "$desired" | tr -d ' ') tracks"
  exit 0
fi

# The CLI can only add or remove one track per call, and an add always appends.
# Clearing and refilling is the only way to keep the playlist in ranked order.
removed=0
while read -r track; do
  [ -n "$track" ] || continue
  spotify_player playlist edit delete "$pid" --track-id "$track" >/dev/null
  removed=$((removed + 1))
done < <(sort -u <<< "$current")

added=0
while read -r track; do
  spotify_player playlist edit add "$pid" --track-id "$track" >/dev/null
  added=$((added + 1))
done <<< "$desired"

echo "playlist: '$name' rebuilt, $removed removed, $added added"
