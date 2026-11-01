#!/usr/bin/env python3
"""Track ids for the Gig Scouting playlist, one per line, in order.

The acts of every gig in New announcements and Coming up, gigs in page order
and acts within a gig best first, taking tracks_per_act of each act's top
tracks: one track from every act before a second from any, so the start of the
playlist covers the whole list. Acts without a score (no data) are skipped. A
track is kept once, where it first appears. At most max_tracks (100).

Top tracks come from wherever the act's payload already is: cache/artists for
known artists, cache/discover for the discovery list, gig_acts.json for the
rest. No calls.
"""

import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(root, "gigs", "lib"))
from names import norm  # noqa: E402

cfg = json.load(open(os.path.join(root, "gigs.json")))
per = cfg.get("playlist", {}).get("tracks_per_act", 2)
max_tracks = cfg.get("playlist", {}).get("max_tracks", 100)
recs = json.load(open(os.path.join(root, "gig_recs.json")))
acts_db = json.load(open(os.path.join(root, "gig_acts.json")))


def top_tracks(act):
    if act.get("id"):
        for folder in ("artists", "discover"):
            p = os.path.join(root, "cache", folder, act["id"] + ".json")
            if os.path.exists(p):
                return [t["id"] for t in json.load(open(p)).get("top_tracks", [])]
    return acts_db.get(norm(act["name"]), {}).get("top_tracks", [])


order, seen_acts = [], set()
for g in recs["new"] + recs["coming"]:
    for a in sorted(g["acts"], key=lambda a: -(a.get("score") or 0)):
        if a.get("score") is None or norm(a["name"]) in seen_acts:
            continue
        seen_acts.add(norm(a["name"]))
        order.append(top_tracks(a))

out, seen = [], set()
for rnd in range(per):
    for tracks in order:
        if rnd < len(tracks) and tracks[rnd] not in seen:
            seen.add(tracks[rnd])
            out.append(tracks[rnd])
# Capped: the CLI adds one track per call, so length is time and rate limit.
print("\n".join(out[:max_tracks]))
