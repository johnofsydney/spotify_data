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
# Makes my playlist called NAME hold exactly those tracks, creating it if
# missing. Found by name among my own playlists, so no id is stored. Needs
# SPOTIFY_USER_ID.
#
# The CLI adds or removes one track per call, and an add always appends, so
# the playlist is updated rather than rebuilt: tracks no longer wanted are
# removed, new ones are added at the end, and the rest stay put. A weekly
# change is a few dozen calls instead of a few hundred. The cost is order: a
# fresh playlist is in ranked order, and after that newcomers join at the end.
# SPOTIFY_PROGRESS_EVERY (default 25) sets how often progress is printed.
sync_playlist() {
  local name="$1" description="$2" public="${3:-0}"
  local desired pid current drop add n_drop n_add done every track
  desired=$(cat)
  if [ -z "$desired" ]; then
    echo "playlist: no tracks for '$name', leaving it alone" >&2
    return 1
  fi
  every="${SPOTIFY_PROGRESS_EVERY:-25}"

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
  # Set differences, keeping the desired order for what is added.
  # (An empty pattern list would match everything, so an empty playlist is
  # handled on its own.)
  if [ -z "$current" ]; then
    drop=""
    add="$desired"
  else
    drop=$(grep -vxF -f <(printf '%s\n' "$desired") <<< "$current" | sort -u || true)
    add=$(grep -vxF -f <(printf '%s\n' "$current") <<< "$desired" || true)
  fi
  n_drop=$(grep -c . <<< "$drop" || true)
  n_add=$(grep -c . <<< "$add" || true)
  if [ "$n_drop" -eq 0 ] && [ "$n_add" -eq 0 ]; then
    echo "playlist: '$name' unchanged, $(grep -c . <<< "$desired") tracks"
    return 0
  fi
  echo "playlist: '$name' updating, $n_drop to remove, $n_add to add"

  done=0
  while read -r track; do
    [ -n "$track" ] || continue
    sp playlist edit delete "$pid" --track-id "$track" >/dev/null
    done=$((done + 1))
    [ $((done % every)) -eq 0 ] && echo "playlist: '$name' removed $done/$n_drop"
  done <<< "$drop"

  done=0
  while read -r track; do
    [ -n "$track" ] || continue
    sp playlist edit add "$pid" --track-id "$track" >/dev/null
    done=$((done + 1))
    [ $((done % every)) -eq 0 ] && echo "playlist: '$name' added $done/$n_add"
  done <<< "$add"

  echo "playlist: '$name' updated, $n_drop removed, $n_add added"
}
