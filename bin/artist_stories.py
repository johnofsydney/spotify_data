#!/usr/bin/env python3
"""A one- or two-sentence story for each ranked artist: why they sit where they do.

Deterministic and offline. It reads only what a refresh has already written:

  favourite_artists.json     signals and points per artist
  yearly_artists.json        tracks per year in the "Your Top Songs" wraps
  cache/yearly/*.json        which wrap years exist
  top_tracks_artists_*.md    one file per weekly run: who was in the top 50
  history/rankings.csv       the weekly top 50, for rank movement

The same files always give the same stories. Each artist gets the first
archetype whose rule matches, in the order below, then up to one extra clause
(rank movement, a Best Of playlist, a run of new releases). Thresholds are named
constants so the rules can be read and tuned in one place.

Writes artist_stories.json: {artist name: {"archetype", "label", "story"}}.
The archetype is a stable key; the label is how the page heads the story.
"""

import csv
import glob
import json
import os
import re

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BINGE_TOP = 5          # top-50 tracks that make "right now" the whole story
BINGE_MAX_YEARS = 1    # ...when they have at most this many wraps behind them
LONG_HAUL_YEARS = 5    # wraps that make a long-standing favourite
GAP_YEARS = 2          # missing from this many latest wraps counts as a gap
COLLECTED_YEARLY_SHARE = 0.15   # yearly points below this share of the score...
COLLECTED_FILED_SHARE = 0.6     # ...with playlists and flags above this share
HAND_PICKED_SHARE = 0.25        # favourites-playlist points as a share of score
MOVE_PLACES = 5        # rank change worth mentioning


def load(path, default):
    return json.load(open(path)) if os.path.exists(path) else default


def wraps_of(spec):
    """'2025x1 2018x3' -> {2025: 1, 2018: 3}"""
    out = {}
    for part in (spec or "").split():
        m = re.fullmatch(r"(\d{4})x(\d+)", part)
        if m:
            out[int(m.group(1))] = int(m.group(2))
    return out


def plural(n, word, words=None):
    return f"{n} {word if n == 1 else (words or word + 's')}"


def top_history():
    """{artist: [weeks in the top 50, out of N runs]}, oldest run first."""
    files = sorted(glob.glob(os.path.join(root, "top_tracks_artists_*.md")))
    runs = []
    for f in files:
        names = set()
        for line in open(f, encoding="utf-8"):
            m = re.match(r"^\s*\d+x\s+(.*\S)\s*$", line)
            if m:
                names.add(m.group(1))
        runs.append(names)
    return runs


def rank_moves():
    """{artist: (previous rank or None, current rank)} from the last two runs."""
    path = os.path.join(root, "history", "rankings.csv")
    if not os.path.exists(path):
        return {}
    by_date = {}
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            by_date.setdefault(row["date"], {})[row["artist"]] = int(row["rank"])
    dates = sorted(by_date)
    if len(dates) < 2:
        return {}
    prev, cur = by_date[dates[-2]], by_date[dates[-1]]
    return {a: (prev.get(a), r) for a, r in cur.items()}


PHRASES = {
    "yearly": "years of listening in the wraps",
    "top": "what you are playing right now",
    "spread": "how many of your playlists they turn up in",
    "tracks": "the sheer number of their tracks in your playlists",
    "favourite": "your hand-kept favourites playlist",
    "followed": "a follow",
    "dedicated": "a playlist that is mostly theirs",
    "activity": "a run of new releases",
}


def story(a, wraps, latest, n_wraps, runs, move):
    w = wraps_of(wraps.get(a["name"], {}).get("years"))
    years = sorted(w)
    n_years = len(years)
    first, last = (years[0], years[-1]) if years else (None, None)
    peak = max(years, key=lambda y: (w[y], y)) if years else None
    top = a.get("top", 0)
    score = a["score"] or 1
    pts = a.get("points", {})
    share = {k: (v or 0) / score for k, v in pts.items()}
    weeks = sum(1 for r in runs if a["name"] in r)

    if top >= BINGE_TOP and n_years <= BINGE_MAX_YEARS:
        archetype = "binge"
        past = "never in a wrap" if not years else f"in only the {first} wrap"
        text = (f"A binge: {top} of your top 50 right now, but {past}. "
                f"Could fade as fast as it came.")
    elif top >= BINGE_TOP:
        archetype = "riding high"
        text = (f"Riding high: {top} of your top 50 now, on top of "
                f"{plural(n_years, 'wrap')} since {first}.")
    elif top >= 1 and years and last <= latest - GAP_YEARS:
        archetype = "comeback"
        text = (f"Back after a gap: last in a wrap in {last}, now "
                f"{plural(top, 'track')} in your top 50.")
    elif n_years >= LONG_HAUL_YEARS:
        archetype = "long haul"
        now = (f"still in your top 50 now ({top})" if top else "quiet right now")
        text = (f"The long haul: in {n_years} of your {n_wraps} wraps since {first}, "
                f"biggest in {peak}; {now}.")
    elif n_years >= 2 and last <= latest - GAP_YEARS and top == 0:
        archetype = "faded"
        held = max((k for k in PHRASES if k != "yearly"), key=lambda k: share.get(k, 0))
        when = (f"last in a wrap in {last}" if peak == last
                else f"biggest in {peak}, not in a wrap since {last}")
        text = f"Faded: {when}. Kept up here by {PHRASES[held]}."
    elif years and first >= latest - 1 and top >= 1:
        archetype = "rising"
        text = (f"Rising: first wrap {first}, and {plural(top, 'track')} in your top 50 now.")
    elif share.get("yearly", 0) < COLLECTED_YEARLY_SHARE and top == 0 and \
            sum(share.get(k, 0) for k in ("spread", "tracks", "favourite", "dedicated")) > COLLECTED_FILED_SHARE:
        archetype = "collected"
        where = plural(a.get("spread", 0), "playlist")
        fav = ", and on your favourites list" if a.get("favourite") else ""
        text = (f"Collected more than played: in {where}{fav}, "
                f"but {'never' if not years else 'rarely'} in the wraps.")
    elif a.get("favourite") and share.get("favourite", 0) >= HAND_PICKED_SHARE:
        archetype = "hand-picked"
        text = (f"Hand-picked: your favourites playlist is "
                f"{round(share['favourite'] * 100)}% of the score.")
    elif top >= 1 and n_years == 0:
        archetype = "new"
        text = f"New: {plural(top, 'track')} in your top 50, nothing in the wraps yet."
    else:
        # No single story: say what carries them, in that signal's own terms.
        big = max(PHRASES, key=lambda k: share.get(k, 0))
        archetype = "steady"
        if big == "yearly" and n_years == 1:
            text = f"One big year: {plural(w[first], 'track')} in the {first} wrap."
        elif big == "yearly":
            text = f"A wraps regular: in {n_years} of them, most recently {last}."
        elif big == "spread":
            text = (f"A playlist regular: in {plural(a.get('spread', 0), 'playlist')}"
                    + (f", last in a wrap in {last}." if years else ", never in a wrap."))
        elif big == "tracks":
            text = (f"Deep in your playlists: {plural(a.get('tracks', 0), 'track')} across them"
                    + (f", last in a wrap in {last}." if years else "."))
        elif big == "followed":
            text = "Mostly a follow; little of them in your listening."
        else:
            text = f"Mostly on {PHRASES[big]}."
            if years:
                text += f" In {plural(n_years, 'wrap')}, last {last}."

    extra = None
    if move:
        prev, cur = move
        if prev is None:
            extra = "New to the top 50 this week."
        elif prev - cur >= MOVE_PLACES:
            extra = f"Up {prev - cur} places this week."
        elif cur - prev >= MOVE_PLACES:
            extra = f"Down {cur - prev} places this week."
    if not extra and len(runs) >= 4 and archetype == "binge" and weeks >= 4:
        extra = f"In your top 50 {weeks} weeks running, so maybe not a phase."
    if not extra and a.get("dedicated") and archetype not in ("collected",):
        extra = "Has a playlist that is mostly theirs."
    if not extra and (a.get("activity") or 0) >= 0.75 and archetype in ("long haul", "steady", "hand-picked", "riding high"):
        extra = "Releasing a lot lately."
    # Most stories open "Label: …". The label is shown on its own above the
    # story, so it moves out of the text; the archetype stays as a stable key.
    label = archetype.capitalize()
    if ": " in text.split(".")[0]:
        label, text = text.split(": ", 1)
        text = text[0].upper() + text[1:]
    return archetype, label, text + (" " + extra if extra else "")


def main():
    favs = load(os.path.join(root, "favourite_artists.json"), {"artists": []})["artists"]
    wraps = load(os.path.join(root, "yearly_artists.json"), {})
    wrap_years = sorted(int(os.path.basename(f)[:4]) for f in glob.glob(os.path.join(root, "cache", "yearly", "*.json")))
    latest = wrap_years[-1] if wrap_years else 0
    runs = top_history()
    moves = rank_moves()
    out = {}
    for a in favs:
        archetype, label, text = story(a, wraps, latest, len(wrap_years), runs, moves.get(a["name"]))
        out[a["name"]] = {"archetype": archetype, "label": label, "story": text}
    with open(os.path.join(root, "artist_stories.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    counts = {}
    for v in out.values():
        counts[v["archetype"]] = counts.get(v["archetype"], 0) + 1
    print(f"stories: {len(out)} artists, {dict(sorted(counts.items(), key=lambda x: -x[1]))}")


if __name__ == "__main__":
    main()
