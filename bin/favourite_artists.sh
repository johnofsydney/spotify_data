#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/favourite_artists.md"
weights_file="$root/weights.json"
playlist_weights_file="$root/playlist_weights.json"

min_tracks="${MIN_TRACKS:-3}"
ded_share="${DED_SHARE:-0.5}"
ded_size="${DED_SIZE:-5}"

# Accepts weights summing to 1 or to 100; anything else is a mistake, not a scale.
w=$(jq '
  ([.[]] | add) as $sum
  | if ($sum - 1 | fabs) < 0.0001 then .
    elif ($sum - 100 | fabs) < 0.0001 then map_values(. / 100)
    else error("weights must sum to 1 or 100, got \($sum)")
    end' "$weights_file")

top_file=$(ls -1 "$root"/top_tracks_artists_*.md | sort | tail -1)

counted() {
  jq -Rn '[inputs
    | capture("^(?<n>[0-9]+)x  (?<name>.*)$")
    | {key: .name, value: (.n | tonumber)}] | from_entries' "$1"
}

top=$(counted "$top_file")
liked=$(counted "$root/liked_tracks_artists.md")
followed=$(jq -Rn '[inputs | select(length > 0)]' "$root/followed_artists.md")
pw=$([ -f "$playlist_weights_file" ] && jq 'map_values(.weight)' "$playlist_weights_file" || echo '{}')

playlists=$(jq -s --argjson w "$pw" '
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
  --argjson liked "$liked" \
  --argjson playlists "$playlists" \
  --argjson followed "$followed" \
  --argjson dedicated "$dedicated" \
  --argjson w "$w" \
  --argjson min "$min_tracks" '
  def norm($n; $max): if $max > 0 then (($n / $max) | sqrt) else 0 end;

  ($followed | map({key: ., value: true}) | from_entries) as $fol
  | ($dedicated | map({key: ., value: true}) | from_entries) as $ded
  | ([($top | keys), ($liked | keys), ($playlists | keys), $followed, $dedicated]
      | add | unique) as $names
  | ([$top[]] | max // 0) as $maxtop
  | ([$liked[]] | max // 0) as $maxliked
  | ([$playlists[].tracks] | max // 0) as $maxtracks
  | ([$playlists[].spread] | max // 0) as $maxspread
  | $names
  | map(. as $n
      | ($top[$n] // 0) as $t
      | ($liked[$n] // 0) as $l
      | ($playlists[$n].tracks // 0) as $pt
      | ($playlists[$n].spread // 0) as $ps
      | (if $fol[$n] then 1 else 0 end) as $f
      | (if $ded[$n] then 1 else 0 end) as $d
      | select($t > 0 or $f > 0 or $d > 0 or $pt >= $min
               or ($w.liked > 0 and $l > 0))
      | [(100 * ($w.top * norm($t; $maxtop)
               + $w.liked * norm($l; $maxliked)
               + $w.spread * norm($ps; $maxspread)
               + $w.tracks * norm($pt; $maxtracks)
               + $w.followed * $f
               + $w.dedicated * $d)), $n, $t, $l, $ps, $pt, $f, $d])
  | sort_by(-.[0], (.[1] | ascii_downcase))
  | .[] | @tsv' |
awk -F'\t' '
  BEGIN { printf "%4s  %6s  %-42s %5s %6s %7s %7s %4s %4s\n", "#", "score", "artist", "top", "liked", "spread", "tracks", "fol", "ded"
          printf "%4s  %6s  %-42s %5s %6s %7s %7s %4s %4s\n", "----", "------", "------------------------------------------", "---", "-----", "------", "------", "---", "---" }
  { printf "%4d  %6.1f  %-42s %5d %6d %7.1f %7.1f %4s %4s\n", NR, $1, $2, $3, $4, $5, $6, ($7 == 1 ? "y" : "n"), ($8 == 1 ? "y" : "n") }
' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) artists -> $out"
