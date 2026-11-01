#!/usr/bin/env bash
set -euo pipefail

# Rebuilds the "Gig Scouting" playlist from gig_recs.json: a couple of tracks
# from every scored act in New announcements and Coming up, to hear who is
# playing before deciding. Never counted as taste: playlist_artists.sh skips it
# by name, as it does Worth Investigating.

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=/dev/null
[ -f "$root/.env" ] && . "$root/.env"
: "${SPOTIFY_USER_ID:?not set — copy .env.example to .env and fill it in}"
# shellcheck source=lib_spotify.sh
. "$root/bin/lib_spotify.sh"

name=$(jq -r '.playlist.name // "Gig Scouting"' "$root/gigs.json")
per=$(jq -r '.playlist.tracks_per_act // 2' "$root/gigs.json")
description="Rebuilt weekly by spotify_data: ${per} tracks from each act in the coming-up and newly announced Sydney gigs it recommends."

python3 "$root/gigs/playlist_tracks.py" | sync_playlist "$name" "$description" 0
