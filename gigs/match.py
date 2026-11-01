#!/usr/bin/env python3
"""Matches every act in gig_listings.json to a Spotify artist, into gig_acts.json.

In order:
  1. Known artists (cache/artists, the favourites ranking) by name. No call.
  2. The discovery list by name. No call.
  3. A previous lookup in gig_acts.json younger than cache_days. No call.
  4. Otherwise a Spotify search, accepting exact name matches only:
     - one match: taken;
     - several: each candidate's related artists are fetched and the one most
       like my favourites is taken, marked as a guess (scoring discounts it);
     - none: recorded as unmatched, so it is not searched again for a month.
     A matched act's related artists and top tracks are kept in the record, so
     scoring and the playlist need no further calls.

New lookups are capped per run (max_new_lookups), soonest gigs and headliners
first, because each is a call or two on a client id shared with every
spotify_player user. Acts past the cap wait for the next run and show as "not
looked up yet".
"""

import datetime
import glob
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(root, "gigs", "lib"))
from names import clean, norm  # noqa: E402
import spotify  # noqa: E402

cfg = json.load(open(os.path.join(root, "gigs.json")))
OUT = os.path.join(root, "gig_acts.json")
MAX_CANDIDATES = 4


def load(path, default):
    return json.load(open(path)) if os.path.exists(path) else default


def compact(payload):
    return {
        "related": [{"id": a["id"], "name": a["name"]} for a in payload.get("related_artists", [])],
        "top_tracks": [t["id"] for t in payload.get("top_tracks", [])][:5],
    }


def main():
    today = datetime.date.today()
    max_age = datetime.timedelta(days=cfg["matching"].get("cache_days", 30))
    budget = cfg["matching"].get("max_new_lookups", 400)

    known = {}
    for path in glob.glob(os.path.join(root, "cache", "artists", "*.json")):
        a = json.load(open(path)).get("artist") or {}
        if a.get("id"):
            known[norm(a["name"])] = {"id": a["id"], "name": a["name"]}
    fav_names = [a["name"] for a in load(os.path.join(root, "favourite_artists.json"), {"artists": []})["artists"]]
    fav_set = {norm(n) for n in fav_names}
    for n in fav_names:
        known.setdefault(norm(n), {"id": None, "name": n})
    discovery = {norm(a["name"]): {"id": a["id"], "name": a["name"]}
                 for a in load(os.path.join(root, "discover_artists.json"), [])}

    previous = load(OUT, {})
    gigs = load(os.path.join(root, "gig_listings.json"), [])

    # Every act once, ordered soonest gig first, headliners before supports.
    order, first = [], {}
    for g in gigs:
        for i, act in enumerate(g["acts"]):
            k = norm(act["name"])
            if k and k not in first:
                first[k] = clean(act["name"])
                order.append((g["start"], 0 if act["billing"] == "headline" else 1, i, k))
    order.sort()

    acts, stats = {}, {"known": 0, "discovery": 0, "cached": 0, "looked_up": 0, "pending": 0}
    for _, _, _, k in order:
        name = first[k]
        if k in known:
            acts[k] = {"name": name, "kind": "known", **known[k]}
            stats["known"] += 1
            continue
        if k in discovery:
            acts[k] = {"name": name, "kind": "discovery", **discovery[k]}
            stats["discovery"] += 1
            continue
        prev = previous.get(k)
        if prev and prev.get("checked") and \
                today - datetime.date.fromisoformat(prev["checked"]) < max_age:
            acts[k] = prev
            stats["cached"] += 1
            continue
        if budget <= 0:
            acts[k] = {"name": name, "kind": "pending"}
            stats["pending"] += 1
            continue
        budget -= 1
        try:
            acts[k] = lookup(name, k, fav_set)
        except spotify.SpotifyError as e:
            print(f"match: {name}: {e}", file=sys.stderr)
            acts[k] = prev or {"name": name, "kind": "pending"}
            stats["pending"] += 1
            continue
        acts[k]["checked"] = today.isoformat()
        stats["looked_up"] += 1

    # Keep month-old lookups for acts not playing this week too: they come round.
    for k, v in previous.items():
        if k not in acts and v.get("checked") and \
                today - datetime.date.fromisoformat(v["checked"]) < max_age:
            acts[k] = v

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(acts.items())), f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"gig acts: {len(order)} this run; {stats}", file=sys.stderr)


def lookup(name, k, fav_set):
    matches = [a for a in spotify.search_artists(name) if norm(a["name"]) == k]
    # Search can return one artist twice across result types; keep each id once.
    seen, uniq = set(), []
    for a in matches:
        if a["id"] not in seen:
            seen.add(a["id"])
            uniq.append(a)
    if not uniq:
        return {"name": name, "kind": "unmatched"}
    if len(uniq) == 1:
        p = spotify.artist(uniq[0]["id"])
        return {"name": name, "kind": "similar", "id": uniq[0]["id"], "guess": False, **compact(p or {})}
    best, best_overlap = None, -1
    for a in uniq[:MAX_CANDIDATES]:
        p = spotify.artist(a["id"]) or {}
        c = compact(p)
        overlap = sum(1 for r in c["related"] if norm(r["name"]) in fav_set)
        # Ties go to the candidate with more related artists: an established
        # act is a likelier booking than a namesake with no footprint.
        if (overlap, len(c["related"])) > (best_overlap, len((best or {}).get("related", []))):
            best, best_overlap = {"id": a["id"], **c}, overlap
    return {"name": name, "kind": "similar", "guess": True, "candidates": len(uniq), **best}


if __name__ == "__main__":
    main()
