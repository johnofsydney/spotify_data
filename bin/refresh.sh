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
# Network, but only for the head of the discovery list. Without it the album list
# falls back to artists I already know rather than failing the run.
./bin/fetch_discover.sh || echo "DISCOVER FETCH FAILED - albums use known artists only"
./bin/album_recs.sh
# Gigs: listings from every source, then Spotify matching (network, capped per
# run), then offline scoring. A failed source keeps last week's listings.
./bin/fetch_gigs.sh || echo "GIG SOURCES FAILED - see above; scoring what there is"
python3 gigs/match.py || echo "GIG MATCHING FAILED - scoring with last week's matches"
python3 gigs/score.py
python3 gigs/calendar.py
./bin/record_history.sh
python3 bin/artist_stories.py
./bin/build_page.sh
# Changes Spotify, not this repository, so a failure is logged rather than
# allowed to cost the week's commit.
./bin/discover_playlist.sh || echo "PLAYLIST FAILED - exports still committed"
./bin/gig_playlist.sh || echo "GIG PLAYLIST FAILED - exports still committed"

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
