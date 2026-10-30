#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "=== refresh $(date '+%F %T') ==="

./bin/followed_artists.sh
./bin/liked_tracks_artists.sh
./bin/top_tracks_artists.sh
./bin/alltime_artists.sh
./bin/yearly_artists.sh
./bin/playlist_artists.sh
./bin/artist_details.sh "${ARTIST_LIMIT:-99999}"
./bin/sync_playlist_weights.sh
./bin/favourite_artists.sh
./bin/discover_artists.sh
./bin/record_history.sh
./bin/build_page.sh
# Changes Spotify, not this repository, so a failure is logged rather than
# allowed to cost the week's commit.
./bin/discover_playlist.sh || echo "PLAYLIST FAILED - exports still committed"

if [ -z "$(git status --porcelain)" ]; then
  echo "no changes"
  exit 0
fi

git add -A
git commit -q -m "Refresh exports $(date +%F)"
echo "committed $(git rev-parse --short HEAD)"

# A scheduled run has no terminal to report a failed push to, so say so in the log
# and leave the commit for the next run to carry.
if git push -q 2>&1; then
  echo "pushed"
else
  echo "PUSH FAILED - commit is local only"
fi
