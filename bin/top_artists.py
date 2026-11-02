#!/usr/bin/env python3
"""Spotify's own top artists, in all three windows, into top_artists.json.

spotify_player's CLI has no top-artists key, and its top tracks come only in
Spotify's default window (medium term, about six months). This asks the Web API
directly for /me/top/artists in short_term (about four weeks), medium_term
(about six months) and long_term (about a year and more), 50 each.

It borrows the login spotify_player already holds: the cached Web API token in
~/.cache/spotify-player/<client id>_token.json, which carries the user-top-read
scope. It never refreshes that token itself (a refresh can rotate the refresh
token and log spotify_player out); refresh.sh runs a spotify_player call just
before this, which refreshes the cache when needed. If the token is missing or
expired, or the file format has changed, it says so and exits cleanly, leaving
last run's file in place; favourite_artists.sh ignores a file over 14 days old.

The token file is spotify_player's internal state, not a published interface,
so this is the part to check first if a spotify_player upgrade breaks the run.
"""

import datetime
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(root, "top_artists.json")
CACHE = os.environ.get("SPOTIFY_PLAYER_CACHE", os.path.expanduser("~/.cache/spotify-player"))
# spotify_player's bundled Web API client id (ncspot's), used unless one is configured.
DEFAULT_CLIENT = "d420a117a32841c2b3474932e49fb54b"
WINDOWS = ("short_term", "medium_term", "long_term")


def skip(why):
    print(f"top artists: skipped, {why}", file=sys.stderr)
    sys.exit(0)


def token():
    files = [os.path.join(CACHE, f"{DEFAULT_CLIENT}_token.json")]
    files += sorted(glob.glob(os.path.join(CACHE, "*_token.json")))
    for path in files:
        if not os.path.exists(path):
            continue
        try:
            t = json.load(open(path))
            access = t["access_token"]
            expires = t.get("expires_at")
        except (ValueError, KeyError):
            continue
        if expires:
            # RFC 3339 from chrono: "Z", and up to nine fractional digits,
            # which older Pythons will not parse.
            stamp = re.sub(r"(\.\d{6})\d+", r"\1", expires.replace("Z", "+00:00"))
            when = datetime.datetime.fromisoformat(stamp)
            if when <= datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=30):
                continue
        return access
    return None


def get(url, access):
    for attempt in range(5):
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access}"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                time.sleep(int(e.headers.get("Retry-After", 5 * 2 ** attempt)))
                continue
            raise


def main():
    if not os.path.isdir(CACHE):
        skip(f"no spotify_player cache at {CACHE}")
    access = token()
    if not access:
        skip("no unexpired spotify_player token (run any spotify_player command first)")
    out = {"fetched": datetime.date.today().isoformat(), "windows": {}}
    try:
        for w in WINDOWS:
            data = get(f"https://api.spotify.com/v1/me/top/artists?time_range={w}&limit=50", access)
            out["windows"][w] = [{"rank": i + 1, "id": a["id"], "name": a["name"]}
                                 for i, a in enumerate(data.get("items", []))]
            time.sleep(0.5)
    except urllib.error.HTTPError as e:
        skip(f"Spotify answered {e.code} for top artists")
    except (urllib.error.URLError, ValueError, KeyError) as e:
        skip(f"could not read top artists ({e})")
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    sizes = ", ".join(f"{w.split('_')[0]} {len(v)}" for w, v in out["windows"].items())
    print(f"top artists: {sizes} -> {OUT}")


if __name__ == "__main__":
    main()
