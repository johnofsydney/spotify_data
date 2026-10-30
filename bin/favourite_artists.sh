#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/favourite_artists.md"
weights_file="$root/weights.json"
playlist_weights_file="$root/playlist_weights.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --weights) weights_file="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) echo "usage: $(basename "$0") [--weights FILE] [--out FILE]" >&2; exit 64 ;;
  esac
done

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
                 spread: ((group_by(.pl) | map(select(length >= 2) | .[0].pw) | add) // 0)}})
  | from_entries' "$root"/cache/playlists/*.json)

# Spotify's typ does not distinguish a reissue from new work, so a heritage act's
# remaster churn reads as activity. Counting releases over a window discriminates
# where a latest-release date cannot: a reissued back catalogue is sporadic.
activity=$([ -d "$root/cache/artists" ] && jq -s --arg since "$(date -v-${ACTIVITY_YEARS:-3}y +%F 2>/dev/null || date -d "${ACTIVITY_YEARS:-3} years ago" +%F)" '
  def fresh: select(.name | test("remaster|remix|anniversar|deluxe|edition|collection|greatest|best of|live at|live in|live from|the complete|volume|vol\\.|singles|b-sides|rarit|reissue|demos|studio demo|original recording|sessions|unreleased|outtake|\\bmix\\)|\\bmix$"; "i") | not);
  [.[] | {key: .artist.name,
          value: (([.albums[] | fresh | select(.typ == "album"  and .release_date > $since)] | length) as $a
                | ([.albums[] | fresh | select(.typ == "single" and .release_date > $since)] | length) as $s
                | [$a / 2 + $s / 12, 1] | min)}]
  | from_entries' "$root"/cache/artists/*.json || echo '{}')

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
  --argjson activity "$activity" \
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
  | ([$activity[]] | max // 0) as $maxact
  | $names
  | map(. as $n
      | ($top[$n] // 0) as $t
      | ($liked[$n] // 0) as $l
      | ($playlists[$n].tracks // 0) as $pt
      | ($playlists[$n].spread // 0) as $ps
      | (if $fol[$n] then 1 else 0 end) as $f
      | (if $ded[$n] then 1 else 0 end) as $d
      | ($activity[$n] // 0) as $act
      | select($t > 0 or $f > 0 or $d > 0 or $pt >= $min
               or ($w.liked > 0 and $l > 0))
      | [(100 * ($w.top * norm($t; $maxtop)
               + $w.liked * norm($l; $maxliked)
               + $w.spread * norm($ps; $maxspread)
               + $w.tracks * norm($pt; $maxtracks)
               + $w.followed * $f
               + $w.dedicated * $d
               + $w.activity * norm($act; $maxact))), $n, $t, $l, $ps, $pt, $f, $d, $act])
  | sort_by(-.[0], (.[1] | ascii_downcase))
  | .[] | @tsv' |
awk -F'\t' '
  BEGIN { printf "%4s  %6s  %-42s %5s %6s %7s %7s %4s %4s %6s\n", "#", "score", "artist", "top", "liked", "spread", "tracks", "fol", "ded", "rel3y"
          printf "%4s  %6s  %-42s %5s %6s %7s %7s %4s %4s %6s\n", "----", "------", "------------------------------------------", "---", "-----", "------", "------", "---", "---", "-----" }
  { printf "%4d  %6.1f  %-42s %5d %6d %7.1f %7.1f %4s %4s %6.2f\n", NR, $1, $2, $3, $4, $5, $6, ($7 == 1 ? "y" : "n"), ($8 == 1 ? "y" : "n"), $9 }
' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) artists -> $out"
