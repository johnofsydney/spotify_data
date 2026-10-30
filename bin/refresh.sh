#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

./bin/followed_artists.sh
./bin/liked_tracks_artists.sh
./bin/top_tracks_artists.sh
./bin/playlist_artists.sh
./bin/artist_details.sh "${ARTIST_LIMIT:-250}"
./bin/sync_playlist_weights.sh
./bin/favourite_artists.sh

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "Refresh exports $(date +%F)"
  echo "committed $(date +%F)"
else
  echo "no changes $(date +%F)"
fi
