"""The shared gig shape every source adapter writes.

Downstream scripts read only this, so an adapter's whole job is to turn its
source into a list of these dicts. Keep it to the standard library: the
adapters run on a stock Mac with nothing installed.
"""

import json
import sys
import urllib.request

USER_AGENT = "spotify_data gig picker (github.com/johnofsydney/spotify_data)"


def gig(source, source_id, start, venue, acts, *, venue_id=None, address=None,
        suburb=None, url=None, free=False, title=None):
    """start: an aware ISO 8601 datetime string, e.g. 2026-11-14T20:00:00+11:00.
    acts: [{"name": str, "billing": "headline" | "support"}], headliners first."""
    return {
        "source": source,
        "source_id": str(source_id),
        "start": start,
        "date": start[0:10],
        "time": start[11:16],
        "venue": venue,
        "venue_id": venue_id,
        "address": address,
        "suburb": suburb,
        "acts": acts,
        "url": url,
        "free": bool(free),
        "title": title,
    }


def fetch(url, headers=None, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8")


def emit(gigs):
    json.dump(gigs, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")


def config():
    """Each adapter is called with its own block of gigs.json as argv[1]."""
    return json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
