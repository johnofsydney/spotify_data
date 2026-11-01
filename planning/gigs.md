# Gig recommendations — design

Settled decisions, stage by stage. Not built yet. What is still open, or
decided only for now, is in [open_questions.md](open_questions.md).

## 1. Listings

- **Sources are adapters.** One script per source in `gigs/sources/`, each
  writing gigs in one shared shape, one JSON object per gig:

  ```json
  {"source": "sydneymusic", "source_id": "…", "date": "2026-11-14",
   "time": "20:00", "venue": "Factory Theatre",
   "acts": [{"name": "Negative Approach", "billing": "headline"},
            {"name": "Rapid Dye", "billing": "support"}],
   "url": "…", "free": false}
  ```

  Everything downstream reads only this shape and never knows the source.
- **Config picks sources and modes.** `gigs.json`, e.g.
  `"sydneymusic": {"enabled": true, "mode": "scrape"}`. Keys live in `.env`.
- **Adding a source** is a new adapter and a config line. `fetch_gigs.sh` runs
  every enabled adapter, merges, and de-duplicates on date + venue + headliner,
  keeping the fuller line-up when two sources list one show.

### SydneyMusic.net — scrape now, API later
- The adapter has two backends behind one entry point, chosen by `mode`.
  Switching to their API (they offer to license one) is a new backend, a config
  flip and a key in `.env`; nothing downstream changes.
- `/gig-guide` is one page holding about two months (1,113 gigs on
  1 Nov 2026), so a run is one request. robots.txt allows everything.
- The raw HTML is kept per run, so a parser fix can be re-run without
  re-fetching.
- A sharp drop in the gig count against last week fails loudly and keeps last
  week's gigs rather than writing an empty list.

### Ticketmaster Discovery API
- Music events within a radius of the inner city, twelve months ahead, queried a
  month at a time (the API will not page past 1,000 results). About a dozen calls
  a week against a free limit of 5,000 a day.
- Catches big shows months before SydneyMusic lists them, which is what makes
  "a band I love, three months out" possible.
- Tribute and covers shows are dropped by event name ("tribute", "plays the
  music of", "experience" and similar). SydneyMusic already excludes them.

## 2. Matching acts to Spotify

- Split headliner from supports at "W/"; strip country tags like "(USA)".
- Look the name up among known artists (`cache/artists`) and the discovery list
  first.
- Otherwise search Spotify and accept exact name matches only.
- **Several matches:** take the best guess (most overlap between its related
  artists and my favourites) and mark it as a guess.
- Lookups cached for 30 days, so only new names cost a call after the first run.

## 3. Scoring

All on the favourites' 0-100 scale.

- **Known artist:** their favourite score.
- **On the discovery list:** discovery score, scaled so the top one is 40.
- **Unknown, on Spotify:** discovery-style score from their related artists —
  favourites Spotify says they resemble vote for them, weighted by rank — on the
  same 40 ceiling.
- **Not on Spotify, or no related artists:** "no data", not zero.
- **Guessed matches:** × 0.7.
- **An act scores the same headlining or supporting.**
- **Gig score:** best act + 0.3 × the sum of the other acts.

## 4. Ranking and the page

Three sections:

- **New announcements** — gigs by top-100 favourites not seen in last week's
  run, however far ahead.
- **Coming up** — the next 8 weeks, ranked by gig score, above a minimum score.
- **Further out** — beyond 8 weeks, above the minimum, by date.

Plus a collapsed list of "no data" gigs underneath.

- **Area:** inner west and eastern suburbs only. Ticketmaster's radius does the
  rough cut; a venue exclusion list does the rest.
- **Price:** SydneyMusic's FREE flag shown as a tag; no price filtering.

## 5. Output

Not discussed yet.
