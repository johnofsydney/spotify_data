#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$root/playlist_weights.json"

existing=$([ -f "$file" ] && cat "$file" || echo '{}')

jq -S -s --argjson old "$existing" '
  map({key: .playlist.id,
       value: {name: .playlist.name,
               tracks: (.tracks | length)}
              + (if $old[.playlist.id] then
                   {weight: $old[.playlist.id].weight}
                   + (if $old[.playlist.id].favourites then {favourites: true} else {} end)
                   + (if $old[.playlist.id].reviewed == false then {reviewed: false} else {} end)
                 else
                   {weight: 0, reviewed: false}
                 end)})
  | from_entries' "$root"/cache/playlists/*.json > "$file.tmp"

added=$(jq -n --argjson o "$existing" --slurpfile n "$file.tmp" '[$n[0] | keys[]] - [$o | keys[]] | length')
removed=$(jq -n --argjson o "$existing" --slurpfile n "$file.tmp" '[$o | keys[]] - [$n[0] | keys[]] | length')
mv "$file.tmp" "$file"
echo "playlist weights: $(jq 'length' "$file") playlists, $added added, $removed removed"

unreviewed=$(jq -r '[to_entries[] | select(.value.reviewed == false) | .value.name] | "\(length) unreviewed: \(join(", "))"' "$file")
echo "playlist weights: $unreviewed"
