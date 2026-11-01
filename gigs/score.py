#!/usr/bin/env python3
"""Scores every gig against my taste into gig_recs.json and gig_recs.md. Offline.

An act scores on the favourites' 0-100 scale:
  known      their favourite score.
  discovery  their discovery score, scaled so the top discovery artist scores
             unknown_ceiling (40).
  similar    the discovery method applied to a stranger: every favourite that
             is related to them, either way round (in their related artists, or
             listing them in its own), votes its score. Scaled like discovery
             and capped at unknown_ceiling.
  no data    unmatched on Spotify, not looked up yet, or matched with no
             related artists in either direction. Not the same as zero.
Guessed matches are multiplied by guess_discount. An act scores the same
headlining or supporting.

A gig scores its best act plus support_share of the next support_count (3)
best acts. Sections:
  new        gigs with a top-favourite_alert_rank favourite that were not in
             last run's list, however far ahead.
  coming     the next coming_up_weeks weeks, at least min_gig_score, best first.
  later      further ahead, at least min_gig_score, by date.
  nodata     gigs where no act could be scored, by date.
"""

import datetime
import glob
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(root, "gigs", "lib"))
from names import norm  # noqa: E402

cfg = json.load(open(os.path.join(root, "gigs.json")))
S = cfg["scoring"]
SEEN = os.path.join(root, "history", "gig_alerts_seen.json")


def load(path, default):
    return json.load(open(path)) if os.path.exists(path) else default


def main():
    favs = load(os.path.join(root, "favourite_artists.json"), {"artists": []})["artists"]
    fav = {norm(a["name"]): {"score": a["score"], "rank": a["rank"], "name": a["name"]} for a in favs}
    disc = load(os.path.join(root, "discover_artists.json"), [])
    disc_max = max([d["score"] for d in disc] or [1])
    ceiling = S["unknown_ceiling"]
    disc_score = {norm(d["name"]): min(ceiling, d["score"] / disc_max * ceiling) for d in disc}
    disc_from = {norm(d["name"]): d.get("from", []) for d in disc}

    # Reverse edges: who among my favourites lists this artist id as related.
    reverse = {}
    for path in glob.glob(os.path.join(root, "cache", "artists", "*.json")):
        p = json.load(open(path))
        f = fav.get(norm((p.get("artist") or {}).get("name", "")))
        if not f or f["score"] <= 0:
            continue
        for r in p.get("related_artists", []):
            reverse.setdefault(r["id"], {})[f["name"]] = f["score"]

    acts = load(os.path.join(root, "gig_acts.json"), {})
    gigs = load(os.path.join(root, "gig_listings.json"), [])

    def score_act(name):
        k = norm(name)
        a = acts.get(k, {"kind": "pending"})
        out = {"name": name, "kind": a["kind"], "id": a.get("id"), "guess": bool(a.get("guess"))}
        if a["kind"] == "known" and k in fav:
            out.update(score=fav[k]["score"], rank=fav[k]["rank"])
        elif a["kind"] == "discovery" and k in disc_score:
            out.update(score=disc_score[k], via=disc_from[k][:3])
        elif a["kind"] == "similar":
            votes = dict(reverse.get(a.get("id"), {}))
            for r in a.get("related", []):
                f = fav.get(norm(r["name"]))
                if f and f["score"] > 0:
                    votes[f["name"]] = f["score"]
            if votes or a.get("related"):
                out["score"] = min(ceiling, sum(votes.values()) / disc_max * ceiling)
                out["via"] = sorted(votes, key=lambda n: -votes[n])[:3]
        if "score" in out:
            if out["guess"]:
                out["score"] *= S["guess_discount"]
            out["score"] = round(out["score"], 1)
        return out

    seen = set(load(SEEN, []))
    first_run = not os.path.exists(SEEN)
    alert_keys = []
    today = datetime.date.today()
    horizon = (today + datetime.timedelta(weeks=S["coming_up_weeks"])).isoformat()
    sections = {"new": [], "coming": [], "later": [], "nodata": []}

    for g in gigs:
        scored = [score_act(a["name"]) | {"billing": a["billing"]} for a in g["acts"]]
        values = sorted([a["score"] for a in scored if "score" in a], reverse=True)
        item = {k: g[k] for k in ("key", "start", "date", "time", "venue", "suburb", "address",
                                  "free", "links", "title")}
        item["acts"] = scored
        if not values:
            item["score"] = None
            sections["nodata"].append(item)
            continue
        # Only the next few acts add to the best one, or a 30-act festival bill
        # outscores a favourite's headline show on volume alone.
        others = values[1:1 + S.get("support_count", 3)]
        item["score"] = round(values[0] + S["support_share"] * sum(others), 1)
        alert = any(a.get("rank") and a["rank"] <= S["favourite_alert_rank"] for a in scored)
        if alert:
            alert_keys.append(g["key"])
            if g["key"] not in seen:
                item["new"] = True
                sections["new"].append(item)
        if item["score"] >= S["min_gig_score"] or item.get("new"):
            (sections["coming"] if g["date"] <= horizon else sections["later"]).append(item)

    sections["coming"].sort(key=lambda g: (-g["score"], g["start"]))
    pending = sum(1 for g in gigs for a in g["acts"] if acts.get(norm(a["name"]), {}).get("kind", "pending") == "pending")
    out = {"generated": today.isoformat(), "first_run": first_run, "horizon": horizon,
           "pending_acts": pending, "listed": len(gigs), **sections}
    with open(os.path.join(root, "gig_recs.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.makedirs(os.path.dirname(SEEN), exist_ok=True)
    with open(SEEN, "w") as f:
        json.dump(sorted(set(alert_keys)), f, indent=0)
        f.write("\n")
    write_md(out)
    print(f"gig recs: {len(sections['new'])} new, {len(sections['coming'])} coming up, "
          f"{len(sections['later'])} further out, {len(sections['nodata'])} no data, "
          f"{pending} acts not looked up yet", file=sys.stderr)


def who(g):
    return " / ".join(a["name"] for a in g["acts"])


def why(g):
    bits = []
    for a in g["acts"]:
        if "score" not in a or a["score"] < 1:
            continue
        if a["kind"] == "known":
            bits.append(f"{a['name']}: favourite #{a['rank']}")
        elif a.get("via"):
            bits.append(f"{a['name']}: like {', '.join(a['via'])}" + (" (guess)" if a["guess"] else ""))
    return "; ".join(bits)


def write_md(out):
    rows = [f"# Gigs — {out['generated']}", ""]
    for title, key in (("New announcements", "new"), ("Coming up", "coming"), ("Further out", "later")):
        rows += [f"## {title}", "", "| Date | Score | Line-up | Venue | Why |", "| --- | --- | --- | --- | --- |"]
        for g in out[key]:
            rows.append(f"| {g['date']} {g['time']} | {g['score']} | {who(g)} | {g['venue']} | {why(g)} |")
        rows.append("")
    rows += [f"## No data ({len(out['nodata'])})", "",
             "Acts Spotify cannot place yet. Listed on the page; not repeated here.", ""]
    with open(os.path.join(root, "gig_recs.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows))


if __name__ == "__main__":
    main()
