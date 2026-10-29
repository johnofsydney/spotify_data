#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/playlists"
out="$root/playlist_artists.md"

force=0
if [ "${1:-}" = "--force" ]; then
  force=1
elif [ -n "${1:-}" ]; then
  echo "usage: $(basename "$0") [--force]" >&2
  exit 64
fi

mkdir -p "$cache"

listing=$(spotify_player get key user-playlists)
ids=$(jq -r '.[].id' <<< "$listing" | sort)

fetched=0
reused=0
while IFS=$'\t' read -r id snapshot; do
  file="$cache/$id.json"
  cached=$(jq -r '.playlist.snapshot_id // empty' "$file" 2>/dev/null || true)
  if [ "$force" -eq 0 ] && [ "$cached" = "$snapshot" ]; then
    reused=$((reused + 1))
    continue
  fi
  # Stage then move: an interrupted fetch must not leave a file that later passes the snapshot check.
  spotify_player get item -i "$id" playlist > "$file.tmp"
  mv "$file.tmp" "$file"
  fetched=$((fetched + 1))
done < <(jq -r '.[] | [.id, .snapshot_id] | @tsv' <<< "$listing")

pruned=0
for file in "$cache"/*.json; do
  [ -e "$file" ] || continue
  if ! grep -qxF "$(basename "$file" .json)" <<< "$ids"; then
    rm "$file"
    pruned=$((pruned + 1))
  fi
done

jq -s -r '
  [.[].tracks[].artists[].name]
  | group_by(.)
  | map({name: .[0], n: length})
  | sort_by(-.n, (.name|ascii_downcase))[]
  | "\(.n)x  \(.name)"' "$cache"/*.json > "$out"

echo "$(wc -l < "$out" | tr -d ' ') artists -> $out"
echo "playlists: $fetched fetched, $reused cached, $pruned pruned"
