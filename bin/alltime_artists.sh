#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/special"
out="$root/alltime_artists.md"

# shellcheck source=/dev/null
[ -f "$root/.env" ] && . "$root/.env"

if [ -z "${ALLTIME_PLAYLIST_ID:-}" ]; then
  echo "ALLTIME_PLAYLIST_ID unset - skipping"
  exit 0
fi

mkdir -p "$cache"
file="$cache/alltime.json"

# Spotify owns and regenerates this playlist, so it is fetched every run rather
# than cached against a snapshot: the snapshot changing is the thing we watch.
previous=$(jq -r '.playlist.snapshot_id // ""' "$file" 2>/dev/null || echo "")
spotify_player get item -i "$ALLTIME_PLAYLIST_ID" playlist |
  jq 'del(.playlist.owner, .playlist.owner_id)' > "$file.tmp"
mv "$file.tmp" "$file"
current=$(jq -r '.playlist.snapshot_id' "$file")

jq -r '[.tracks[].artists[].name]
  | group_by(.)
  | map({name: .[0], n: length})
  | sort_by(-.n, (.name | ascii_downcase))[]
  | "\(.n)x  \(.name)"' "$file" > "$out"

log="$root/history/alltime_snapshots.csv"
mkdir -p "$(dirname "$log")"
[ -f "$log" ] || echo "date,snapshot_id,tracks,changed" > "$log"
changed=$([ -n "$previous" ] && [ "$previous" != "$current" ] && echo yes || echo no)
echo "$(date +%F),$current,$(jq '.tracks|length' "$file"),$changed" >> "$log"

echo "$(wc -l < "$out" | tr -d ' ') artists -> $out (snapshot changed: $changed)"
