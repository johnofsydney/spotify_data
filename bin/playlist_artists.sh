#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/playlists"
out="$root/playlist_artists.md"

# shellcheck source=/dev/null
[ -f "$root/.env" ] && . "$root/.env"
: "${SPOTIFY_USER_ID:?not set — copy .env.example to .env and fill it in}"
# Written by discover_playlist.sh from the discovery ranking, not chosen by me.
# Caching it would count its artists as known and empty the discovery list.
generated="${DISCOVER_PLAYLIST_NAME:-Worth Investigating}"

force=0
if [ "${1:-}" = "--force" ]; then
  force=1
elif [ -n "${1:-}" ]; then
  echo "usage: $(basename "$0") [--force]" >&2
  exit 64
fi

mkdir -p "$cache"

mine=$(spotify_player get key user-playlists |
  jq --arg me "$SPOTIFY_USER_ID" --arg gen "$generated" \
    '[.[] | select(.owner[1] == $me and .name != $gen) | {id, snapshot_id}]')
ids=$(jq -r '.[].id' <<< "$mine" | sort)

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
  spotify_player get item -i "$id" playlist |
    jq 'del(.playlist.owner, .playlist.owner_id)' > "$file.tmp"
  mv "$file.tmp" "$file"
  fetched=$((fetched + 1))
done < <(jq -r '.[] | [.id, .snapshot_id] | @tsv' <<< "$mine")

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
