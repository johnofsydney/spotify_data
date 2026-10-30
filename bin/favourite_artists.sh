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

json="${out%.md}.json"

min_tracks="${MIN_TRACKS:-3}"
ded_share="${DED_SHARE:-0.5}"
ded_size="${DED_SIZE:-5}"
track_cap="${TRACK_CAP:-5}"

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
alltime=$([ -f "$root/alltime_artists.md" ] && counted "$root/alltime_artists.md" || echo '{}')
# Already decay-weighted by yearly_artists.sh, so it is read as a score rather than counted.
yearly=$([ -f "$root/yearly_artists.json" ] && jq 'map_values(.score)' "$root/yearly_artists.json" || echo '{}')
# How many separate years an artist made the wrap: a plainer fact than the score.
yearly_n=$([ -f "$root/yearly_artists.json" ] && jq 'map_values(.years | split(" ") | length)' "$root/yearly_artists.json" || echo '{}')
liked=$(counted "$root/liked_tracks_artists.md")
followed=$(jq -Rn '[inputs | select(length > 0)]' "$root/followed_artists.md")
pw=$([ -f "$playlist_weights_file" ] && jq 'map_values(.weight)' "$playlist_weights_file" || echo '{}')

# One playlist can say an artist matters; it cannot say so forty-one times. Without
# the cap, tracks measures catalogue size and how thorough a compilation felt on the
# day, which is why an artist barely played in a decade outranked one heavily played.
playlists=$(jq -s --argjson w "$pw" --argjson cap "$track_cap" '
  [.[] | .playlist.id as $id | ($w[$id] // 1) as $pw
       | select($pw > 0)
       | .tracks[].artists[].name | {name: ., pl: $id, pw: $pw}]
  | group_by(.name)
  | map({key: .[0].name,
         value: {tracks: ((group_by(.pl) | map(([length, $cap] | min) * .[0].pw) | add) // 0),
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

fav_ids=$(jq -r 'to_entries | map(select(.value.favourites)) | map(.key) | @json' "$playlist_weights_file")

favourites=$(jq -s --argjson ids "$fav_ids" '
  [.[] | select(.playlist.id | IN($ids[])) | .tracks[].artists[].name] | unique' "$root"/cache/playlists/*.json)

dedicated=$(jq -s --argjson share "$ded_share" --argjson size "$ded_size" '
  [.[] | (.tracks | length) as $n | select($n >= $size)
       | [.tracks[].artists[].name] | group_by(.)
       | map(select((length / $n) > $share) | .[0])[]]
  | unique' "$root"/cache/playlists/*.json)

jq -n -r \
  --argjson top "$top" \
  --argjson alltime "$alltime" \
  --argjson yearly "$yearly" \
  --argjson yearly_n "$yearly_n" \
  --argjson liked "$liked" \
  --argjson playlists "$playlists" \
  --argjson followed "$followed" \
  --argjson dedicated "$dedicated" \
  --argjson favourites "$favourites" \
  --argjson activity "$activity" \
  --argjson w "$w" \
  --argjson min "$min_tracks" '
  def norm($n; $max): if $max > 0 then (($n / $max) | sqrt) else 0 end;

  ($followed | map({key: ., value: true}) | from_entries) as $fol
  | ($dedicated | map({key: ., value: true}) | from_entries) as $ded
  | ($favourites | map({key: ., value: true}) | from_entries) as $favs
  | ([($top | keys), ($liked | keys), ($alltime | keys), ($yearly | keys), ($playlists | keys),
      $followed, $dedicated, $favourites] | add | unique) as $names
  | ([$top[]] | max // 0) as $maxtop
  | ([$alltime[]] | max // 0) as $maxall
  | ([$yearly[]] | max // 0) as $maxyear
  | ([$liked[]] | max // 0) as $maxliked
  | ([$playlists[].tracks] | max // 0) as $maxtracks
  | ([$playlists[].spread] | max // 0) as $maxspread
  | ([$activity[]] | max // 0) as $maxact
  | $names
  | map(. as $n
      | ($top[$n] // 0) as $t
      | ($alltime[$n] // 0) as $at
      | ($yearly[$n] // 0) as $yr
      | ($yearly_n[$n] // 0) as $yn
      | ($liked[$n] // 0) as $l
      | ($playlists[$n].tracks // 0) as $pt
      | ($playlists[$n].spread // 0) as $ps
      | (if $fol[$n] then 1 else 0 end) as $f
      | (if $ded[$n] then 1 else 0 end) as $d
      | (if $favs[$n] then 1 else 0 end) as $fv
      | ($activity[$n] // 0) as $act
      | select($t > 0 or $at > 0 or $yr > 0 or $f > 0 or $d > 0 or $fv > 0 or $pt >= $min
               or ($w.liked > 0 and $l > 0))
      | [(100 * ($w.alltime * norm($at; $maxall)
               + $w.yearly * norm($yr; $maxyear)
               + $w.top * norm($t; $maxtop)
               + $w.liked * norm($l; $maxliked)
               + $w.spread * norm($ps; $maxspread)
               + $w.tracks * norm($pt; $maxtracks)
               + $w.followed * $f
               + $w.dedicated * $d
               + $w.activity * norm($act; $maxact)
               + $w.favourite * $fv)), $n, $at, $t, $l, $ps, $pt, $f, $d, $fv, $act, $yr, $yn])
  | sort_by(-.[0], (.[1] | ascii_downcase))
  | to_entries
  | map({rank: (.key + 1), score: (.value[0] * 10 | round / 10), name: .value[1],
         yearly: .value[11], yearly_years: .value[12], alltime: .value[2], top: .value[3], liked: .value[4], spread: .value[5],
         tracks: .value[6], followed: (.value[7] == 1), dedicated: (.value[8] == 1),
         favourite: (.value[9] == 1), activity: .value[10]})
  | {weights: $w, artists: .}' > "$json"

jq -r '.artists[] | [.score, .name, .yearly, .top, .spread, .tracks,
              (if .followed then 1 else 0 end), (if .dedicated then 1 else 0 end),
              (if .favourite then 1 else 0 end), .activity] | @tsv' "$json" |
awk -F'\t' '
  BEGIN { printf "%4s  %6s  %-38s %7s %5s %7s %7s %4s %4s %4s %6s\n", "#", "score", "artist", "yearly", "top", "spread", "tracks", "fol", "ded", "FAV", "rel3y"
          printf "%4s  %6s  %-38s %7s %5s %7s %7s %4s %4s %4s %6s\n", "----", "------", "--------------------------------------", "-------", "---", "------", "------", "---", "---", "---", "-----" }
  { printf "%4d  %6.1f  %-38s %7.2f %5d %7.1f %7.1f %4s %4s %4s %6.2f\n", NR, $1, $2, $3, $4, $5, $6, ($7 == 1 ? "y" : "n"), ($8 == 1 ? "y" : "n"), ($9 == 1 ? "Y" : "-"), $10 }
' > "$out"

echo "$(( $(wc -l < "$out") - 2 )) artists -> $out"
