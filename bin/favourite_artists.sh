#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/favourite_artists.md"
weights_file="$root/playlist_weights.json"

w_top="${W_TOP:-0.32}"
w_dedicated="${W_DEDICATED:-0.26}"
w_spread="${W_SPREAD:-0.19}"
w_tracks="${W_TRACKS:-0.13}"
w_followed="${W_FOLLOWED:-0.10}"

min_tracks="${MIN_TRACKS:-3}"
ded_share="${DED_SHARE:-0.5}"
ded_size="${DED_SIZE:-5}"

top_file=$(ls -1 "$root"/top_tracks_artists_*.md | sort | tail -1)

top=$(jq -Rn '[inputs
  | capture("^(?<n>[0-9]+)x  (?<name>.*)$")
  | {key: .name, value: (.n | tonumber)}] | from_entries' "$top_file")
followed=$(jq -Rn '[inputs | select(length > 0)]' "$root/followed_artists.md")
weights=$([ -f "$weights_file" ] && jq 'map_values(.weight)' "$weights_file" || echo '{}')

playlists=$(jq -s --argjson w "$weights" '
  [.[] | .playlist.id as $id | ($w[$id] // 1) as $pw
       | select($pw > 0)
       | .tracks[].artists[].name | {name: ., pl: $id, pw: $pw}]
  | group_by(.name)
  | map({key: .[0].name,
         value: {tracks: ([.[].pw] | add),
                 spread: (group_by(.pl) | map(.[0].pw) | add)}})
  | from_entries' "$root"/cache/playlists/*.json)

dedicated=$(jq -s --argjson share "$ded_share" --argjson size "$ded_size" '
  [.[] | (.tracks | length) as $n | select($n >= $size)
       | [.tracks[].artists[].name] | group_by(.)
       | map(select((length / $n) > $share) | .[0])[]]
  | unique' "$root"/cache/playlists/*.json)

jq -n -r \
  --argjson top "$top" \
  --argjson playlists "$playlists" \
  --argjson followed "$followed" \
  --argjson dedicated "$dedicated" \
  --argjson w "{\"top\":$w_top,\"spread\":$w_spread,\"tracks\":$w_tracks,\"followed\":$w_followed,\"dedicated\":$w_dedicated}" \
  --argjson min "$min_tracks" '
  def norm($n; $max): if $max > 0 then (($n / $max) | sqrt) else 0 end;

  ($followed | map({key: ., value: true}) | from_entries) as $fol
  | ($dedicated | map({key: ., value: true}) | from_entries) as $ded
  | ([($top | keys), ($playlists | keys), $followed, $dedicated] | add | unique) as $names
  | ([$top[]] | max // 0) as $maxtop
  | ([$playlists[].tracks] | max // 0) as $maxtracks
  | ([$playlists[].spread] | max // 0) as $maxspread
  | $names
  | map(. as $n
      | ($top[$n] // 0) as $t
      | ($playlists[$n].tracks // 0) as $pt
      | ($playlists[$n].spread // 0) as $ps
      | (if $fol[$n] then 1 else 0 end) as $f
      | (if $ded[$n] then 1 else 0 end) as $d
      | select($t > 0 or $f > 0 or $d > 0 or $pt >= $min)
      | [(100 * ($w.top * norm($t; $maxtop)
               + $w.spread * norm($ps; $maxspread)
               + $w.tracks * norm($pt; $maxtracks)
               + $w.followed * $f
               + $w.dedicated * $d)), $n, $t, $ps, $pt, $f, $d])
  | sort_by(-.[0], (.[1] | ascii_downcase))
  | .[] | @tsv' |
awk -F'\t' '
  BEGIN { printf "%4s  %6s  %-42s %5s %7s %7s %4s %4s\n", "#", "score", "artist", "top", "spread", "tracks", "fol", "ded"
          printf "%4s  %6s  %-42s %5s %7s %7s %4s %4s\n", "----", "------", "------------------------------------------", "---", "------", "------", "---", "---" }
  { printf "%4d  %6.1f  %-42s %5d %7.1f %7.1f %4s %4s\n", NR, $1, $2, $3, $4, $5, ($6 == 1 ? "y" : "n"), ($7 == 1 ? "y" : "n") }
' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) artists -> $out"
