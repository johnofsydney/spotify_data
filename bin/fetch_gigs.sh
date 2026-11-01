#!/usr/bin/env bash
set -euo pipefail

# Runs every enabled gig source in gigs.json, then merges them into
# gig_listings.json. Each source is an adapter in gigs/sources/<name>.py that
# prints gigs in the shared shape (gigs/lib/gigshape.py); this script neither
# knows nor cares how it got them.
#
# A source that fails, or whose gig count falls below min_keep_ratio of last
# run's, keeps last run's gigs and says so loudly. A changed page layout should
# cost a week of freshness, not the whole list.

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$root/cache/gigs"
config="$root/gigs.json"

# shellcheck source=/dev/null
[ -f "$root/.env" ] && set -a && . "$root/.env" && set +a

mkdir -p "$cache" "$cache/raw"
ratio=$(jq -r '.min_keep_ratio // 0.5' "$config")
failed=0

while read -r name; do
  adapter="$root/gigs/sources/$name.py"
  if [ ! -f "$adapter" ]; then
    echo "gigs: no adapter for '$name' at gigs/sources/$name.py" >&2
    failed=1
    continue
  fi
  block=$(jq -c --arg n "$name" --arg raw "$cache/raw" '.sources[$n] + {raw_dir: $raw}' "$config")
  out="$cache/$name.json"
  if ! python3 "$adapter" "$block" > "$out.tmp"; then
    echo "GIGS: $name FAILED - keeping last run's gigs" >&2
    rm -f "$out.tmp"
    failed=1
    continue
  fi
  new=$(jq length "$out.tmp")
  old=$([ -f "$out" ] && jq length "$out" || echo 0)
  if [ "$old" -gt 20 ] && [ "$(jq -n --argjson n "$new" --argjson o "$old" --argjson r "$ratio" '$n < $o * $r')" = true ]; then
    echo "GIGS: $name returned $new gigs against $old last run - keeping last run's (layout change?)" >&2
    rm -f "$out.tmp"
    failed=1
    continue
  fi
  mv "$out.tmp" "$out"
  echo "gigs: $name $new (was $old)"
done < <(jq -r '.sources | to_entries[] | select(.value.enabled) | .key' "$config")

python3 "$root/gigs/merge.py"
exit "$failed"
