"""spotify_player from Python, paced and retried like sp() in bin/lib_spotify.sh.

The CLI's client id is shared by everyone who uses it, so bursts get 429s.
Calls are spaced by SPOTIFY_PACE seconds and a 429 is retried after 5, 10, 20…
seconds, up to SPOTIFY_RETRIES times. Any other failure raises.
"""

import json
import os
import subprocess
import sys
import time


class SpotifyError(RuntimeError):
    pass


def call(*args):
    pace = float(os.environ.get("SPOTIFY_PACE", "0.5"))
    retries = int(os.environ.get("SPOTIFY_RETRIES", "6"))
    wait = 5
    for attempt in range(retries + 1):
        time.sleep(pace)
        p = subprocess.run(["spotify_player", *args], capture_output=True, text=True)
        if p.returncode == 0:
            return json.loads(p.stdout) if p.stdout.strip() else None
        if "429" in p.stderr and attempt < retries:
            print(f"spotify: rate limited, waiting {wait}s (retry {attempt + 1} of {retries})",
                  file=sys.stderr)
            time.sleep(wait)
            wait *= 2
            continue
        raise SpotifyError(f"spotify_player {' '.join(args)}: {p.stderr.strip()}")


def search_artists(query):
    """Artists from `spotify_player search`, as [{"id", "name"}]."""
    data = call("search", query) or {}
    found = data.get("artists", [])
    if isinstance(found, dict):  # tolerate a paged {"items": [...]} shape
        found = found.get("items", [])
    return [{"id": a.get("id"), "name": a.get("name")} for a in found if a.get("id")]


def artist(artist_id):
    """The same payload cache/artists holds: artist, top_tracks, related_artists, albums."""
    return call("get", "item", "-i", artist_id, "artist")
