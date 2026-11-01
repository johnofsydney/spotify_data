#!/usr/bin/env bash
set -euo pipefail

# Twenty albums to listen to in full, from artists I love and artists the
# discovery list points at. Offline: reads the artist caches the other scripts
# fetch, and makes no calls of its own.
#
# The only exclusion is the album club playlist. Everything else is ranking:
# how much I like the artist, how many of their top tracks the album holds, and
# whether it is new. Known-track counts are reported, not used to filter.

root="$(cd "$(dirname "$0")/.." && pwd)"
config="$root/albums.json"
today="${ALBUM_RECS_DATE:-$(date +%F)}"


club_name=$(jq -r '.exclude_playlist' "$config")
club_id=$(jq -r --arg n "$club_name" 'to_entries[] | select(.value.name == $n) | .key' "$root/playlist_weights.json" | head -1)
[ -n "$club_id" ] || echo "albums: no playlist named '$club_name', nothing excluded for it" >&2

# Playlists that count as evidence of listening. Weight 0 marks archives of
# Spotify's own recommendations, which say nothing about what I actually know.
known_ids=$(jq -r 'to_entries[] | select(.value.weight > 0) | .key' "$root/playlist_weights.json")
known_files=()
while read -r id; do
  [ -f "$root/cache/playlists/$id.json" ] && known_files+=("$root/cache/playlists/$id.json")
done <<< "$known_ids"

shopt -s nullglob
discover_files=("$root"/cache/discover/*.json)
shopt -u nullglob
[ ${#discover_files[@]} -gt 0 ] || echo "albums: cache/discover is empty, only known artists considered" >&2

# Titles differ between editions ("Paranoid (2009 Remastered Version)"), so
# albums are compared on artist id plus a title with the edition noise removed.
norm='def norm: ascii_downcase
  | gsub("\\s*[\\(\\[][^\\)\\]]*(remaster|deluxe|edition|anni ?versary|anniversary|expanded|version|mono|stereo|bonus|reissue)[^\\)\\]]*[\\)\\]]"; "")
  | gsub("\\s+-\\s+.*(remaster|deluxe|edition|anni ?versary|anniversary|expanded|version|reissue).*$"; "")
  | gsub("^\\s+|\\s+$"; "");
  def akey: "\(.artists[0].id)|\(.name | norm | gsub(","; ""))";
  def released: (.release_date + "-01-01")[0:10] | strptime("%Y-%m-%d") | mktime;'

known=$(jq -s "$norm"'
  [.[].tracks[]? | select(.album.artists[0].id != null)
   | {k: (.album | akey), t: (.name | norm)}]
  | group_by(.k) | map({key: .[0].k, value: ([.[].t] | unique | length)}) | from_entries' \
  ${known_files[@]+"${known_files[@]}"} "$root"/cache/yearly/*.json)

club=$( [ -n "$club_id" ] && jq "$norm"'[.tracks[].album | akey] | unique' "$root/cache/playlists/$club_id.json" || echo '[]')

# Artist weights on one 0-100 scale. Favourites already are; the discovery score
# is scaled so its top artist sits at discovery_ceiling, roughly where a
# well-liked but not central favourite lands.
weights=$(jq -n --slurpfile f "$root/favourite_artists.json" --slurpfile d "$root/discover_artists.json" --slurpfile c "$config" '
  ($f[0].artists | map({key: .name, value: {w: .score, src: "known"}}) | from_entries) as $fav
  | ($d[0] | (map(.score) | max) as $m
     | map({key: .id, value: {w: (.score / $m * $c[0].discovery_ceiling), src: "new", from: .from}}) | from_entries) as $disc
  | {fav: $fav, disc: $disc}')

{ cat "$root"/cache/artists/*.json; [ ${#discover_files[@]} -gt 0 ] && cat "${discover_files[@]}"; true; } |
jq -s "$norm"'
  ($c[0]) as $cfg | ($w[0]) as $w
  | (now - $cfg.new_release_days * 86400) as $cutoff
  | [ .[] | select(.artist.id != null)
      | . as $a
      | ($w.fav[$a.artist.name] // $w.disc[$a.artist.id]) as $aw
      | select($aw != null and $aw.w > 0)
      | ([$a.top_tracks[]? | select(.album.typ == "album") | .album | akey]) as $hits
      | ([$a.top_tracks[]?] | length | if . == 0 then 10 else . end) as $ntop
      | [ $a.albums[]?
          | select(.typ == "album" and .artists[0].id == $a.artist.id)
              | . + {key: akey} ]
      | group_by(.key)
      | map(sort_by(.release_date) | .[0])
      # "Album: The Encore" and similar re-packagings of an album already listed.
      | ([.[].key]) as $keys
      | map(.key as $x | select([$keys[] | select($x != . and ($x | startswith(. + ":")))] | length == 0))
      | .[]
      | . as $al
      | ([$hits[] | select(. == $al.key)] | length) as $h
      | (($al | released) >= $cutoff) as $new
      | select($club[0] | index($al.key) | not)
      | { artist: $a.artist.name, artist_id: $a.artist.id, album: $al.name, id: $al.id,
          year: $al.release_date[0:4], key: $al.key, source: $aw.src,
          artist_weight: ($aw.w * 10 | round / 10),
          hits: $h, new: $new, known_tracks: ($k[0][$al.key] // 0),
          from: ($aw.from // [] | .[0:3]),
          score: ($aw.w * ($cfg.hit_floor + $h / $ntop) * (if $new then $cfg.new_release_boost else 1 end) * 10 | round / 10) } ]
  | unique_by(.key)
  | sort_by(-.score, .artist)
  | group_by(.artist_id) | map(.[0:$cfg.per_artist]) | add // []
  | sort_by(-.score, .artist)
  | .[0:$cfg.count]
  | to_entries | map(.value + {rank: (.key + 1)})' \
  --slurpfile c "$config" --slurpfile w <(echo "$weights") --slurpfile k <(echo "$known") \
  --slurpfile club <(echo "$club") > "$root/album_recs.json"

{
  echo "# Albums to hear in full — $today"
  echo
  echo "Ranked by how much I like the artist, whether the album holds their best-known"
  echo "tracks, and whether it is new. Excludes only the \"$club_name\" playlist."
  echo
  echo "| # | Album | Artist | Year | Why |"
  echo "| --- | --- | --- | --- | --- |"
  jq -r '.[] | "| \(.rank) | \(.album) | \(.artist) | \(.year) | \(
      [ (if .source == "known" then "favourite (\(.artist_weight))" else "new to me, via \(.from | join(", "))" end),
        (if .hits > 0 then "\(.hits) of their top tracks" else empty end),
        (if .new then "new release" else empty end) ] | join("; ")) |"' "$root/album_recs.json"
} > "$root/album_recs.md"

echo "albums: no playlist named '$club_name', nothing excluded for it" >&2

# Playlists that count as evidence of listening. Weight 0 marks archives of
# Spotify's own recommendations, which say nothing about what I actually know.
known_ids=$(jq -r 'to_entries[] | select(.value.weight > 0) | .key' "$root/playlist_weights.json")
known_files=()
while read -r id; do
  [ -f "$root/cache/playlists/$id.json" ] && known_files+=("$root/cache/playlists/$id.json")
done <<< "$known_ids"

shopt -s nullglob
discover_files=("$root"/cache/discover/*.json)
shopt -u nullglob
[ ${#discover_files[@]} -gt 0 ] || echo "albums: cache/discover is empty, only known artists considered" >&2

# Titles differ between editions ("Paranoid (2009 Remastered Version)"), so
# albums are compared on artist id plus a title with the edition noise removed.
norm='def norm: ascii_downcase
  | gsub("\\s*[\\(\\[][^\\)\\]]*(remaster|deluxe|edition|anni ?versary|anniversary|expanded|version|mono|stereo|bonus|reissue)[^\\)\\]]*[\\)\\]]"; "")
  | gsub("\\s+-\\s+.*(remaster|deluxe|edition|anni ?versary|anniversary|expanded|version|reissue).*$"; "")
  | gsub("^\\s+|\\s+$"; "");
  def akey: "\(.artists[0].id)|\(.name | norm | gsub(","; ""))";
  def released: (.release_date + "-01-01")[0:10] | strptime("%Y-%m-%d") | mktime;'

known=$(jq -s "$norm"'
  [.[].tracks[]? | select(.album.artists[0].id != null)
   | {k: (.album | akey), t: (.name | norm)}]
  | group_by(.k) | map({key: .[0].k, value: ([.[].t] | unique | length)}) | from_entries' \
  ${known_files[@]+"${known_files[@]}"} "$root"/cache/yearly/*.json)

club=$( [ -n "$club_id" ] && jq "$norm"'[.tracks[].album | akey] | unique' "$root/cache/playlists/$club_id.json" || echo '[]')

# Artist weights on one 0-100 scale. Favourites already are; the discovery score
# is scaled so its top artist sits at discovery_ceiling, roughly where a
# well-liked but not central favourite lands.
weights=$(jq -n --slurpfile f "$root/favourite_artists.json" --slurpfile d "$root/discover_artists.json" --slurpfile c "$config" '
  ($f[0].artists | map({key: .name, value: {w: .score, src: "known"}}) | from_entries) as $fav
  | ($d[0] | (map(.score) | max) as $m
     | map({key: .id, value: {w: (.score / $m * $c[0].discovery_ceiling), src: "new", from: .from}}) | from_entries) as $disc
  | {fav: $fav, disc: $disc}')

{ cat "$root"/cache/artists/*.json; [ ${#discover_files[@]} -gt 0 ] && cat "${discover_files[@]}"; true; } |
jq -s "$norm"'
  ($c[0]) as $cfg | ($w[0]) as $w
  | (now - $cfg.new_release_days * 86400) as $cutoff
  | [ .[] | select(.artist.id != null)
      | . as $a
      | ($w.fav[$a.artist.name] // $w.disc[$a.artist.id]) as $aw
      | select($aw != null and $aw.w > 0)
      | ([$a.top_tracks[]? | select(.album.typ == "album") | .album | akey]) as $hits
      | ([$a.top_tracks[]?] | length | if . == 0 then 10 else . end) as $ntop
      | [ $a.albums[]?
          | select(.typ == "album" and .artists[0].id == $a.artist.id)
              | . + {key: akey} ]
      | group_by(.key)
      | map(sort_by(.release_date) | .[0])
      # "Album: The Encore" and similar re-packagings of an album already listed.
      | ([.[].key]) as $keys
      | map(.key as $x | select([$keys[] | select($x != . and ($x | startswith(. + ":")))] | length == 0))
      | .[]
      | . as $al
      | ([$hits[] | select(. == $al.key)] | length) as $h
      | (($al | released) >= $cutoff) as $new
      | select($club[0] | index($al.key) | not)
      | { artist: $a.artist.name, artist_id: $a.artist.id, album: $al.name, id: $al.id,
          year: $al.release_date[0:4], key: $al.key, source: $aw.src,
          artist_weight: ($aw.w * 10 | round / 10),
          hits: $h, new: $new, known_tracks: ($k[0][$al.key] // 0),
          from: ($aw.from // [] | .[0:3]),
          score: ($aw.w * ($cfg.hit_floor + $h / $ntop) * (if $new then $cfg.new_release_boost else 1 end) * 10 | round / 10) } ]
  | unique_by(.key)
  | sort_by(-.score, .artist)
  | group_by(.artist_id) | map(.[0:$cfg.per_artist]) | add // []
  | sort_by(-.score, .artist)
  | .[0:$cfg.count]
  | to_entries | map(.value + {rank: (.key + 1)})' \
  --slurpfile c "$config" --slurpfile w <(echo "$weights") --slurpfile k <(echo "$known") \
  --slurpfile club <(echo "$club") > "$root/album_recs.json"

{
  echo "# Albums to hear in full — $today"
  echo
  echo "Ranked by how much I like the artist, whether the album holds their best-known"
  echo "tracks, and whether it is new. Excludes only the \"$club_name\" playlist."
  echo
  echo "| # | Album | Artist | Year | Why |"
  echo "| --- | --- | --- | --- | --- |"
  jq -r '.[] | "| \(.rank) | \(.album) | \(.artist) | \(.year) | \(
      [ (if .source == "known" then "favourite (\(.artist_weight))" else "new to me, via \(.from | join(", "))" end),
        (if .hits > 0 then "\(.hits) of their top tracks" else empty end),
        (if .new then "new release" else empty end) ] | join("; ")) |"' "$root/album_recs.json"
} > "$root/album_recs.md"

# One row per album per run date; a rerun on the same day replaces that day.
tmp="$hist.tmp"
awk -F',' -v d="$today" 'NR==1 || $1 != d' "$hist" > "$tmp"
jq -r --arg d "$today" '.[] | "\($d),\(.key),\(.rank),\([.artist, .album] | @csv)"' "$root/album_recs.json" >> "$tmp"
mv "$tmp" "$hist"

echo "albums: $(jq length "$root/album_recs.json") recommended"
