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
