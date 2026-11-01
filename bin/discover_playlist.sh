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

# shellcheck source=lib_spotify.sh
. "$root/bin/lib_spotify.sh"

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

public=0
[ "${DISCOVER_PLAYLIST_PUBLIC:-0}" = "1" ] && public=1
sync_playlist "$name" "$description" "$public" <<< "$desired"
