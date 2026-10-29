#!/usr/bin/env bash
set -euo pipefail

out="$(dirname "$0")/../top_tracks_artists_$(date +%F).md"

spotify_player get key user-top-tracks | jq -r '
  to_entries
  | map(.key as $i | .value.artists[] | {name, i:$i})
  | group_by(.name)
  | map({name: .[0].name, n: length, best: (map(.i)|min)})
  | sort_by(-.n, .best)[]
  | "\(.n)x  \(.name)"' > "$out"

echo "$(wc -l < "$out" | tr -d ' ') artists -> $out"
