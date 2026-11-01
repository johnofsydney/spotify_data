#!/usr/bin/env python3
"""Merges every enabled source's gigs into gig_listings.json.

Drops past gigs, gigs outside the area (suburb list in gigs.json), excluded
venues (exclude/gig_venues.txt) and tribute or covers shows (skip_titles), then
de-duplicates across sources. A band rarely plays two Sydney shows on one day,
so the same date and headliner is treated as one gig; the fuller line-up is
kept, and every source's link is kept with it.
"""

import datetime
import json
import os
import re
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cfg = json.load(open(os.path.join(root, "gigs.json")))
sys.path.insert(0, os.path.join(root, "gigs", "lib"))
from names import slug  # noqa: E402


def lines(path):
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        return {l.strip() for l in f if l.strip() and not l.startswith("#")}


def main():
    today = datetime.date.today().isoformat()
    suburbs = {s.lower() for s in cfg["area"]["suburbs"]}
    keep_unknown = cfg["area"].get("keep_unknown_suburb", True)
    venues_out = lines(os.path.join(root, "exclude", "gig_venues.txt"))
    skip = re.compile(cfg.get("skip_titles", r"$^"), re.I)

    dropped = {"past": 0, "area": 0, "venue": 0, "tribute": 0}
    merged, sources = {}, {}
    for name, src in cfg["sources"].items():
        path = os.path.join(root, "cache", "gigs", f"{name}.json")
        if not src.get("enabled") or not os.path.exists(path):
            continue
        gigs = json.load(open(path))
        sources[name] = len(gigs)
        for g in gigs:
            if g["date"] < today:
                dropped["past"] += 1
                continue
            sub = (g.get("suburb") or "").lower()
            if (sub and sub not in suburbs) or (not sub and not keep_unknown):
                dropped["area"] += 1
                continue
            if g.get("venue") in venues_out or g.get("venue_id") in venues_out:
                dropped["venue"] += 1
                continue
            if skip.search(g.get("title") or "") or skip.search(g["acts"][0]["name"]):
                dropped["tribute"] += 1
                continue
            key = f"{g['date']}-{slug(g['acts'][0]['name'])}"
            link = {"source": g["source"], "url": g.get("url")}
            if key in merged:
                old = merged[key]
                links = old["links"] + [link]
                keep = g if len(g["acts"]) > len(old["acts"]) else old
                merged[key] = {**keep, "key": key, "links": links,
                               "free": old["free"] or g["free"],
                               "suburb": old.get("suburb") or g.get("suburb"),
                               "address": old.get("address") or g.get("address")}
            else:
                merged[key] = {**g, "key": key, "links": [link]}

    out = sorted(merged.values(), key=lambda g: (g["start"], g["key"]))
    with open(os.path.join(root, "gig_listings.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    both = sum(1 for g in out if len({l["source"] for l in g["links"]}) > 1)
    print(f"gigs: {len(out)} listed from {sources}, {both} in more than one source; "
          f"dropped {dropped}", file=sys.stderr)


if __name__ == "__main__":
    main()
