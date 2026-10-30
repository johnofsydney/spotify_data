# spotify_data

A periodic, programmatic export of my Spotify listening data, kept as plain text
so it can be handed to an AI as context about my musical taste.

The questions it exists to answer:

- **What else would I like?** Recommendations grounded in what I actually listen
  to, rather than in what a streaming service wants to promote.
- **Which gigs should I go to?** Both for artists I already follow, and for
  artists I have never heard of whose profile fits the taste described here.

Everything here is derived from the Spotify API via
[`spotify_player`](https://github.com/aome510/spotify-player). Nothing is hand-maintained.

## Setup

Copy `.env.example` to `.env` and fill in your Spotify user ID. `.env` is
gitignored and is the only place any identifier of mine is stored.

```sh
cp .env.example .env
```

## Exports

| Script | Output | Notes |
| --- | --- | --- |
| `bin/followed_artists.sh` | `followed_artists.md` | Artists I follow. Overwrites. |
| `bin/liked_tracks_artists.sh` | `liked_tracks_artists.md` | Artists by liked-track count. Overwrites. |
| `bin/top_tracks_artists.sh` | `top_tracks_artists_<date>.md` | Artists in my top tracks. Dated, one file per run. |
| `bin/playlist_artists.sh` | `playlist_artists.md` | Artists across all playlists. Caches; `--force` to refetch. |
| `bin/favourite_artists.sh` | `favourite_artists.md` | Weighted ranking. Offline. Weights in `weights.json`. |

Run them in that order; `favourite_artists.sh` reads the files the others write
and makes no network calls of its own.

### Why the playlist export caches

Artists are not on the `user-playlists` listing — they are on each individual
playlist, so a full export is one API call per playlist and takes about five
minutes. The listing does carry each playlist's `snapshot_id`, and that value
matches the one inside the playlist payload, so a cached copy stays valid until
the snapshot changes. A warm run takes about five seconds.

Only my own playlists are fetched or kept. Of 111 playlists in the account, 41
belong to Spotify or to other people; those describe an algorithm's taste or a
friend's, not mine, so they are filtered out before anything is written to disk.

`cache/playlists/<id>.json` holds the whole payload rather than just the artist
names, because rebuilding costs five minutes and a cache trimmed to today's
question makes tomorrow's expensive. The owner field is dropped on the way in,
so no user ID — mine or anyone else's — reaches the cache.

The cache is committed, which is deliberate. Spotify exposes no "last modified"
or "last played" date for a playlist, so the commit dates on these files are the
only available record of when a playlist changed — and `git log -p` on one shows
which tracks came and went. That history only runs forward from the first
commit; it says nothing about when a playlist was touched before then.

## The favourites ranking

Four signals disagree about what a favourite is, and none is trustworthy alone.
`favourite_artists.sh` combines them into a single 0–100 score.

| Signal | Weight | What it means |
| --- | --- | --- |
| Top tracks | 0.20 | What I actually play. Spotify returns a short-term window, so this is the only signal that reflects *now* rather than a decision made years ago. Only ever 50 tracks, so it sees a narrow slice. |
| Dedicated playlist | 0.14 | Whether I built a playlist for this artist alone. The most deliberate statement of fandom in the data. |
| Playlist spread | 0.28 | How many *different* playlists an artist appears in. |
| Playlist tracks | 0.20 | How many tracks in total. |
| Followed | 0.12 | Deliberate, but binary and cheap: you follow once and forget. |

| Liked tracks | 0.00 | Off. I rarely use the like button, so the count measured my indifference to a feature rather than my taste. Wired in and displayed, so raising the weight turns it back on. |

Three decisions matter more than the weights:

**A dedicated playlist counts for a lot.** An artist who is more than half of a
playlist of five or more tracks gets the `dedicated` flag. I have fourteen such
playlists, mostly named `BO <artist>`, and building one is a clearer statement
than any number of likes. Detection is by share, not by the naming convention,
so it keeps working if I stop using the `BO` prefix.

**Spread and volume are counted separately.** 52 tracks across 14 playlists means
something different from 54 tracks across 5 — one is an artist I keep reaching
for in different contexts, the other is an album I dumped in once. Counting only
tracks treats them as equal.

**Counts are compressed with a square root** before scaling. 144 tracks does not
mean 144 times the affection of one track; without compression a single
album-length addition buries every other signal.

### Changing the weights

Weights live in `weights.json`, one line per signal, and nowhere else:

```json
{ "top": 0.20, "spread": 0.28, "tracks": 0.20, "dedicated": 0.14,
  "followed": 0.12, "activity": 0.06, "liked": 0.00 }
```

**They must sum to 1, or to 100 if you prefer percentages.** Anything else
fails the run and prints the actual total. The rule is there so that raising one
signal means deciding what to lower, and so that a score stays comparable
between runs — without it, editing a weight silently rescales the whole
ranking and yesterday's 70 no longer means what today's does.

A weight of `0` keeps a signal wired in and displayed while contributing
nothing, which is how liked tracks are handled.

`DED_SHARE` (0.5) and `DED_SIZE` (5) set what counts as a dedicated playlist.
`MIN_TRACKS` (default 3) sets how many playlist appearances an artist needs to
appear at all, absent any other signal. Of the 5,331 artists in my playlists,
3,261 appear exactly once; without a floor the ranking is mostly noise.

### Why these weights, and why they should stay put

They are not the best weights. No weighting of this data is right, because the
measurement that would settle it — sustained listening over time — does not
exist yet.

Two reference points make the limit concrete. GB3 AU is a niche producer I
played heavily for a few weeks after years away; top tracks is a short-term
window, so that binge reads as the strongest signal in the data. King Buffalo
have been my favourite band for years and tour constantly, but they have ten
deliberately-placed tracks in my playlists, no Best Of, and no studio album
since 2021 — so almost nothing records the fact. Every weighting either ranks
the binge above the favourite or buries both under deep back catalogues.

Top tracks is therefore weighted *low* on purpose. One reading of fifty tracks
is noise. As dated snapshots accumulate it becomes the only honest measure of
what I actually listen to, and its weight should rise as the evidence does.

The weights stay fixed in the meantime. The point of accumulating snapshots is
to see the ranking move; if the model moves too, a change cannot be attributed
to either.

### An activity signal exists and is nearly switched off

`activity` scores recent non-reissue releases. It sits at 0.06 because it is
wrong for the purpose. King Buffalo tour relentlessly and have not released a
studio album since 2021, so a release-based measure of activity demotes exactly
the artist I would most want a gig alert for. Spotify exposes no touring data
at all; this is a proxy that its own reference case disproves.

### Per-playlist weights

`playlist_weights.json` gives every playlist a weight, default `1.0`, applied to
both its track and spread contributions. `0` excludes a playlist entirely, so a
blacklist and a whitelist are both just weights.

It exists because playlists are not equal evidence. `Starred`, `My Shazam
Tracks` and `Liked from Radio` are capture buckets rather than curation, and a
playlist I have not opened in years still counts in full — Spotify exposes no
date to decay it by.

## Data in here

This repository is **private** and must stay that way.

Committed data is Spotify metadata: artist names, track names, album names,
playlist names and playlist IDs. Playlist names do incidentally carry first names
of friends and family.

**No usernames or user IDs are stored.** Other people's playlists are never
fetched, and the owner field is dropped from my own before they are cached. My
own user ID lives in `.env`, which is gitignored.

**No credentials are ever committed.** `spotify_player` keeps its OAuth token
outside this repository, and nothing here reads or copies it.
