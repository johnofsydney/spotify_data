#!/usr/bin/env bash
set -euo pipefail

# Cross-references ai_artists_watchlist.json (artists rumoured or confirmed to
# be AI-generated, kept current by a separate periodic research pass) against
# every artist appearing on my own playlists, in cache/playlists/*.json.
#
# Not a detector: it only catches a name already reported elsewhere. New
# rumours land in ai_artists_watchlist.json before they can be caught here.

root="$(cd "$(dirname "$0")/.." && pwd)"
watchlist="$root/ai_artists_watchlist.json"
out="$root/ai_artists_flagged.json"

norm='ascii_downcase | gsub("[^a-z0-9]+"; " ") | gsub("^ +| +$"; "")'

jq -s --slurpfile w "$watchlist" '
  def norm: '"$norm"';
  (map({playlist: .playlist.name, artists: ([.tracks[].artists[].name] | unique)})) as $pls
  | $w[0] | map(. as $e
      | ($e.name | norm) as $n
      | {name: $e.name, note: $e.note, source: $e.source,
         playlists: [$pls[] | select(.artists | map(norm) | index($n)) | .playlist]}
      | select(.playlists | length > 0))
' "$root"/cache/playlists/*.json > "$out.tmp"
mv "$out.tmp" "$out"

n=$(jq 'length' "$out")
if [ "$n" -eq 0 ]; then
  echo "ai artists: none of $(jq 'length' "$watchlist") watchlisted names found on any playlist"
else
  echo "ai artists: $n watchlisted name(s) found -> $out"
  jq -r '.[] | "  " + .name + ": " + (.playlists | join(", "))' "$out"
fi
