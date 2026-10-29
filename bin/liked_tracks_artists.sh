#!/usr/bin/env bash
set -euo pipefail

out="$(dirname "$0")/../liked_tracks_artists.md"

spotify_player get key user-liked-tracks | jq -r '
  to_entries
  | map(.key as $i | .value.artists[] | {name, i:$i})
  | group_by(.name)
  | map({name: .[0].name, n: length, best: (map(.i)|min)})
  | sort_by(-.n, .best)[]
  | "\(.n)x  \(.name)"' > "$out"

echo "$(wc -l < "$out" | tr -d ' ') artists -> $out"
