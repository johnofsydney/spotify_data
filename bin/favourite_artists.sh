#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/favourite_artists.md"


w_liked="${W_LIKED:-0.30}"
w_top="${W_TOP:-0.25}"
w_spread="${W_SPREAD:-0.20}"
w_tracks="${W_TRACKS:-0.15}"
w_followed="${W_FOLLOWED:-0.10}"
min_tracks="${MIN_TRACKS:-3}"

top_file=$(ls -1 "$root"/top_tracks_artists_*.md | sort | tail -1)

counted() {
  jq -Rn '[inputs
    | capture("^(?<n>[0-9]+)x  (?<name>.*)$")
    | {key: .name, value: (.n | tonumber)}] | from_entries' "$1"
}

liked=$(counted "$root/liked_tracks_artists.md")
top=$(counted "$top_file")
followed=$(jq -Rn '[inputs | select(length > 0)]' "$root/followed_artists.md")
playlists=$(jq -s '
  [.[] | . as $p
       | .tracks[].artists[].name | {name: ., pl: $p.playlist.id}]
  | group_by(.name)
  | map({key: .[0].name,
         value: {tracks: length, spread: ([.[].pl] | unique | length)}})
  | from_entries' "$root"/cache/playlists/*.json)

jq -n -r \
  --argjson liked "$liked" \
  --argjson top "$top" \
  --argjson playlists "$playlists" \
  --argjson followed "$followed" \
  --argjson w "{\"liked\":$w_liked,\"top\":$w_top,\"spread\":$w_spread,\"tracks\":$w_tracks,\"followed\":$w_followed}" \
  --argjson min "$min_tracks" '
  def norm($n; $max): if $max > 0 then (($n / $max) | sqrt) else 0 end;

  ($followed | map({key: ., value: true}) | from_entries) as $fol
  | ([($liked | keys), ($top | keys), ($playlists | keys), $followed] | add | unique) as $names
  | ([$liked[]] | max // 0) as $maxliked
  | ([$top[]] | max // 0) as $maxtop
  | ([$playlists[].tracks] | max // 0) as $maxtracks
  | ([$playlists[].spread] | max // 0) as $maxspread
  | $names
  | map(. as $n
      | ($liked[$n] // 0) as $l
      | ($top[$n] // 0) as $t
      | ($playlists[$n].tracks // 0) as $pt
      | ($playlists[$n].spread // 0) as $ps
      | (if $fol[$n] then 1 else 0 end) as $f
      | select($l > 0 or $t > 0 or $f > 0 or $pt >= $min)
      | [(100 * ($w.liked * norm($l; $maxliked)
               + $w.top * norm($t; $maxtop)
               + $w.spread * norm($ps; $maxspread)
               + $w.tracks * norm($pt; $maxtracks)
               + $w.followed * $f)), $n, $l, $t, $ps, $pt, $f])
  | sort_by(-.[0], (.[1] | ascii_downcase))
  | .[] | @tsv' |
awk -F'\t' '
  BEGIN { printf "%4s  %6s  %-44s %6s %5s %7s %7s %4s\n", "#", "score", "artist", "liked", "top", "spread", "tracks", "fol"
          printf "%4s  %6s  %-44s %6s %5s %7s %7s %4s\n", "----", "------", "--------------------------------------------", "-----", "---", "------", "------", "---" }
  { printf "%4d  %6.1f  %-44s %6d %5d %7d %7d %4s\n", NR, $1, $2, $3, $4, $5, $6, ($7 == 1 ? "y" : "n") }
' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) artists -> $out"
