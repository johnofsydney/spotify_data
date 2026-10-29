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
| `bin/favourite_artists.sh` | `favourite_artists.md` | Weighted ranking across all of the above. Offline. |

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
| Liked tracks | 0.30 | A deliberate, per-track endorsement. The most honest signal. |
| Top tracks | 0.25 | What Spotify says I actually play — but only ever 50 tracks, so it sees a narrow slice. |
| Playlist spread | 0.20 | How many *different* playlists an artist appears in. |
| Playlist tracks | 0.15 | How many tracks in total. |
| Followed | 0.10 | Deliberate, but binary and cheap: you follow once and forget. |

Two decisions matter more than the weights:

**Spread and volume are counted separately.** 52 tracks across 14 playlists means
something different from 54 tracks across 5 — one is an artist I keep reaching
for in different contexts, the other is an album I dumped in once. Counting only
tracks treats them as equal.

**Counts are compressed with a square root** before scaling. 144 tracks does not
mean 144 times the affection of one track; without compression a single
album-length addition buries every other signal.

Every weight is an environment variable, so the model can be argued with:

```sh
W_LIKED=0.5 W_TOP=0.3 W_SPREAD=0.1 W_TRACKS=0.05 W_FOLLOWED=0.05 ./bin/favourite_artists.sh
```

`MIN_TRACKS` (default 3) sets how many playlist appearances an artist needs to
appear at all, absent any other signal. Of the 5,331 artists in my playlists,
3,261 appear exactly once; without a floor the ranking is mostly noise.

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
