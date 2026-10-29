#!/usr/bin/env bash
set -euo pipefail

out="$(dirname "$0")/../followed_artists.md"

spotify_player get key user-followed-artists | jq -r '
  map(.name)
  | sort_by(ascii_downcase)[]' > "$out"

echo "$(wc -l < "$out" | tr -d ' ') artists -> $out"
