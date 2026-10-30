#!/usr/bin/env bash
set -euo pipefail

# Does the discovery ranking point at artists I actually went on to keep?
#
# "BO Discover Weekly" is the record of that: artists found through Discover Weekly
# and saved, and never ones I already knew. Spotify does not expose when a track was
# added, but position is a reliable proxy - the artists in each successive quarter of
# the playlist chart in successively later yearly wraps - so the last quarter is the
# most recent discoveries.
#
# Those artists are removed from a copy of the data and the real ranking is run over
# it, which is the state I was in before I found them. A hit is one coming back as a
# recommendation. Chance is the yardstick: without it a hit rate means nothing.

root="$(cd "$(dirname "$0")/.." && pwd)"
bodw_id="${BODW_ID:-0y1swFUZtekVKzOgApO2rz}"
scratch="${SCRATCH:-$(mktemp -d)}"

bodw="$root/cache/playlists/$bodw_id.json"
[ -f "$bodw" ] || { echo "no such playlist: $bodw" >&2; exit 1; }

# Held out: the most recent quarter, limited to artists who appear nowhere else, so
# removing them disturbs nothing but the discovery itself.
holdout=$(jq -s --arg id "$bodw_id" '
  ([.[] | select(.playlist.id == $id) | .tracks[].artists[].name]) as $all
  | ($all[(($all | length) * 3 / 4 | floor):] | unique) as $recent
  | ([.[] | select(.playlist.id != $id) | .tracks[].artists[].name] | unique) as $elsewhere
  | [$recent[] | select(. as $a | $elsewhere | index($a) | not)]' "$root"/cache/playlists/*.json)
n_holdout=$(jq 'length' <<< "$holdout")

echo "holdout: $n_holdout artists from the most recent quarter of BO Discover Weekly"
echo "scratch: $scratch"

mkdir -p "$scratch/cache/playlists"
ln -sfn "$root/cache/artists" "$scratch/cache/artists"
cp "$root/weights.json" "$root/playlist_weights.json" "$scratch/"
[ -f "$root/discover_exclude.txt" ] && cp "$root/discover_exclude.txt" "$scratch/"

# Drop every track crediting a held-out artist. A co-credited track goes too: had I
# never found the artist, I would not hold the track either.
for f in "$root"/cache/playlists/*.json; do
  jq --argjson h "$holdout" '
    ($h | map({key: ., value: true}) | from_entries) as $hx
    | .tracks |= map(select([.artists[].name] | any($hx[.]) | not))' "$f" > "$scratch/cache/playlists/$(basename "$f")"
done

jq --argjson h "$holdout" 'with_entries(select(.key as $k | $h | index($k) | not))' \
  "$root/yearly_artists.json" > "$scratch/yearly_artists.json"

strip_counted() {
  awk -v names="$(jq -r '.[]' <<< "$holdout" | tr '\n' '\036')" '
    BEGIN { n = split(names, a, "\036"); for (i = 1; i <= n; i++) if (a[i] != "") drop[a[i]] = 1 }
    { line = $0; sub(/^[0-9]+x  /, "", line); if (!(line in drop)) print }' "$1"
}
strip_counted "$root/liked_tracks_artists.md" > "$scratch/liked_tracks_artists.md"
strip_counted "$root/alltime_artists.md"      > "$scratch/alltime_artists.md"
strip_counted "$root/followed_artists.md"     > "$scratch/followed_artists.md"
latest_top=$(ls -1 "$root"/top_tracks_artists_*.md | sort | tail -1)
strip_counted "$latest_top" > "$scratch/$(basename "$latest_top")"

DATA_ROOT="$scratch" "$root/bin/favourite_artists.sh" >/dev/null
DATA_ROOT="$scratch" DISCOVER_LIMIT=1000000 "$root/bin/discover_artists.sh" >/dev/null

pool=$(jq 'length' "$scratch/discover_artists.json")
echo "candidate pool after removal: $pool artists"
echo

printf "%6s  %6s  %8s  %8s  %s\n" "top k" "hits" "recall" "chance" "lift"
printf "%6s  %6s  %8s  %8s  %s\n" "-----" "----" "------" "------" "----"
for k in 50 100 150 300 500; do
  hits=$(jq --argjson h "$holdout" --argjson k "$k" \
    '[.[0:$k][].name] as $rec | [$h[] | select(. as $a | $rec | index($a))] | length' "$scratch/discover_artists.json")
  jq -rn --argjson hits "$hits" --argjson k "$k" --argjson n "$n_holdout" --argjson pool "$pool" \
    '($n * $k / $pool) as $exp
     | "\($k | tostring | (" " * (6 - length)) + .)  \($hits | tostring | (" " * (6 - length)) + .)  \((($hits / $n * 1000 | round) / 10 | tostring) + "%" | (" " * (8 - length)) + .)  \((($exp * 10 | round) / 10 | tostring) | (" " * (8 - length)) + .)  \(if $exp > 0 then (($hits / $exp * 10 | round) / 10 | tostring) + "x" else "-" end)"'
done

# A miss that is nowhere in the pool is unreachable: no artist I already like points
# at them, so no amount of reordering would ever surface them. That is the blind spot,
# and it is a different problem from ranking them too low.
echo
jq -r --argjson h "$holdout" '
  [.[].name] as $pool
  | [$h[] | select(. as $a | $pool | index($a))] as $reachable
  | ([.[0:150][].name]) as $top150
  | ([$h[] | select(. as $a | $top150 | index($a))] | length) as $hits
  | "reachable at all: \($reachable | length) of \($h | length)   unreachable: \(($h | length) - ($reachable | length))",
    "",
    "Two separate problems, and the first is the larger:",
    "  coverage  - \(($h | length) - ($reachable | length)) of \($h | length) are in no related list of an artist I like, so no reordering can ever reach them",
    "  ranking   - of the \($reachable | length) that are reachable, the top 150 finds \($hits) (\(($hits / ($reachable | length) * 1000 | round) / 10)%)"' "$scratch/discover_artists.json"

echo
echo "hits in the top 150:"
jq -r --argjson h "$holdout" '[.[0:150][] | select(.name as $n | $h | index($n))][] | "  #\(.rank)  \(.name)  (via \(.from | join(", ")))"' "$scratch/discover_artists.json"
