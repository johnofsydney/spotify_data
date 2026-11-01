# shellcheck shell=bash
# Sourced by scripts that make many spotify_player calls in a row.
#
# spotify_player uses a client id shared with every other user of it, so a burst
# of calls (a playlist rebuilt one track at a time) can be refused with 429 Too
# Many Requests. sp() spaces calls out and, on a 429, waits and retries with a
# doubling delay. Any other error fails immediately, as before.
#
#   SPOTIFY_PACE     seconds between calls (default 0.5)
#   SPOTIFY_RETRIES  attempts after a 429 before giving up (default 6: waits of
#                    5, 10, 20, 40, 80 and 160 seconds, about five minutes)

sp() {
  local attempt=0 wait=5 err out status
  local retries="${SPOTIFY_RETRIES:-6}"
  err=$(mktemp)
  while :; do
    sleep "${SPOTIFY_PACE:-0.5}"
    status=0
    out=$(spotify_player "$@" 2> "$err") || status=$?
    if [ "$status" -eq 0 ]; then
      rm -f "$err"
      printf '%s' "$out"
      [ -z "$out" ] || printf '\n'
      return 0
    fi
    if grep -q '429' "$err" && [ "$attempt" -lt "$retries" ]; then
      attempt=$((attempt + 1))
      echo "spotify: rate limited, waiting ${wait}s (retry $attempt of $retries)" >&2
      sleep "$wait"
      wait=$((wait * 2))
      continue
    fi
    cat "$err" >&2
    rm -f "$err"
    return "$status"
  done
}

# sync_playlist NAME DESCRIPTION PUBLIC(0|1) < track ids, one per line, in order
#
# Makes my playlist called NAME hold exactly those tracks in that order,
# creating it if missing. Found by name among my own playlists, so no id is
# stored. Needs SPOTIFY_USER_ID.
#
# The CLI can only add or remove one track per call, and an add always appends.
# So the playlist is kept in order by clearing and refilling it, except when
# what is there is the start of what should be: a run cut short (by a rate
# limit, say) left a correct but partial playlist, and only the rest is added.
sync_playlist() {
  local name="$1" description="$2" public="${3:-0}"
  local desired pid current current_n todo verb removed added track
  desired=$(cat)
  if [ -z "$desired" ]; then
    echo "playlist: no tracks for '$name', leaving it alone" >&2
    return 1
  fi

  _find_playlist() {
    sp get key user-playlists |
      jq -r --arg me "$SPOTIFY_USER_ID" --arg name "$name" \
        '[.[] | select(.owner[1] == $me and .name == $name) | .id] | first // empty'
  }

  pid=$(_find_playlist)
  if [ -z "$pid" ]; then
    if [ "$public" = "1" ]; then
      sp playlist new "$name" "$description" --public >/dev/null
    else
      sp playlist new "$name" "$description" >/dev/null
    fi
    pid=$(_find_playlist)
    [ -n "$pid" ] || { echo "playlist: created '$name' but cannot find it" >&2; return 1; }
    echo "playlist: created '$name' ($pid)"
  fi

  current=$(sp get item -i "$pid" playlist | jq -r '.tracks[].id')
  if [ "$current" = "$desired" ]; then
    echo "playlist: '$name' unchanged, $(grep -c . <<< "$desired") tracks"
    return 0
  fi

  removed=0
  current_n=$(grep -c . <<< "$current" || true)
  if [ "$current_n" -gt 0 ] && [ "$current" = "$(head -n "$current_n" <<< "$desired")" ]; then
    todo=$(tail -n +"$((current_n + 1))" <<< "$desired")
    verb="topped up"
  else
    while read -r track; do
      [ -n "$track" ] || continue
      sp playlist edit delete "$pid" --track-id "$track" >/dev/null
      removed=$((removed + 1))
    done < <(sort -u <<< "$current")
    todo="$desired"
    verb="rebuilt"
  fi

  added=0
  while read -r track; do
    [ -n "$track" ] || continue
    sp playlist edit add "$pid" --track-id "$track" >/dev/null
    added=$((added + 1))
  done <<< "$todo"

  echo "playlist: '$name' $verb, $removed removed, $added added"
}
