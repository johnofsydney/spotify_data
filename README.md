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

## Adapting this for your own account

Everything specific to me lives in configuration, not in the scripts. Fork it,
delete my data, and point it at your account:

1. **Install [`spotify_player`](https://github.com/aome510/spotify-player)** and
   authenticate it. Every export runs through its CLI; nothing here talks to the
   Spotify API directly, and no API key or app registration is needed.
2. **`cp .env.example .env`** and put your Spotify user ID in it. Open your
   profile in Spotify, Share, Copy link to profile — the ID is the last path
   segment. `.env` is gitignored.
3. **Clear my data**: `rm -rf cache history *.md` (keep `README.md`). Everything
   regenerates.
4. **Run `./bin/refresh.sh`.** The first run fetches every playlist and every
   artist's discography and takes roughly half an hour. Later runs take seconds
   unless you have edited playlists.
5. **Look at `playlist_weights.json`.** It lists every playlist at weight 1.0.
   This is where the real tuning is, and the thing to check first is whether you
   archive Discover Weekly — 65% of my tracks and 73% of my artists turned out
   to be those archives, Spotify recommending to me rather than anything I
   chose. Set them to 0. Event playlists, playlists of someone else's taste, and
   anything you have not opened in years are worth zeroing too.
6. **Flag a favourites playlist** by adding `"favourites": true` to its entry.
   Keep it by hand in Spotify. It is the only way to tell the ranking something
   your listening does not record.
7. **Adjust `weights.json` if you disagree with the model.** The weights must
   sum to 1 or to 100; anything else fails the run and prints the total.
8. **`./setup/install-schedule.sh`** once you want it running weekly.

The ranking will be wrong at first and that is expected. It took a dozen rounds
on my own data, and most of what fixed it was discovering which of my playlists
were evidence and which were noise.

## Scheduling

The exports run weekly so that dated top-tracks snapshots accumulate. That
series is the point: Spotify's top-tracks window is short-term, so one reading
cannot tell a few weeks of renewed interest from a lasting favourite, and only
a run of readings can.

```sh
./setup/install-schedule.sh
```

That writes a launchd agent to `~/Library/LaunchAgents/`, pointing at wherever
this repository is checked out, and loads it. Mondays at 11:00, logging to
`.refresh.log`. Check it with `launchctl list | grep spotify-refresh`, force a
run with `launchctl start <label>`, and remove it with `launchctl unload`.

**launchd rather than cron, because this is a laptop.** If the machine is
asleep at the scheduled time, launchd runs the job when it wakes. If it is shut
down, the job runs after the next login. cron simply skips a missed slot and
says nothing, which would cost a snapshot without anyone noticing.

The one case neither handles: launchd fires **once** on return, however many
slots were missed, so a fortnight away is a single catch-up run and one lost
reading. Nothing can recover it — Spotify exposes no history for the window
that passed.

The scheduled run pushes. A failed push is logged and the commit is left for
the following week to carry rather than aborting the run.

## Exports

| Script | Output | Notes |
| --- | --- | --- |
| `bin/followed_artists.sh` | `followed_artists.md` | Artists I follow. Overwrites. |
| `bin/liked_tracks_artists.sh` | `liked_tracks_artists.md` | Artists by liked-track count. Overwrites. |
| `bin/top_tracks_artists.sh` | `top_tracks_artists_<date>.md` | Artists in my top tracks. Dated, one file per run. |
| `bin/alltime_artists.sh` | `alltime_artists.md` | Artists in Spotify's "Your All-Time Top Songs". Logs the snapshot id each run. Scored at zero — see below. |
| `bin/yearly_artists.sh` | `yearly_artists.md` | Artists across every "Your Top Songs &lt;year&gt;" wrap, weighted by recency. Caches; `--force` to refetch. |
| `bin/playlist_artists.sh` | `playlist_artists.md` | Artists across all playlists. Caches; `--force` to refetch. |
| `bin/favourite_artists.sh` | `favourite_artists.md` | Weighted ranking. Offline. Weights in `weights.json`. |
| `bin/discover_artists.sh` | `discover_artists.md` | Artists I do not have, ranked by which of my favourites point at them. Offline. |
| `bin/record_history.sh` | `history/rankings.csv` | Appends the week's top 50 to the time series. Offline. |
| `bin/build_page.sh` | `docs/index.html` | A readable page of the favourites and discoveries. Offline, self-contained. |

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

Nine signals disagree about what a favourite is, and none is trustworthy
alone. `favourite_artists.sh` combines them into a single 0-100 score.

| Signal | Column | Weight | What it means |
| --- | --- | --- | --- |
| Yearly wraps | `yearly` | 0.25 | Their tracks across every "Your Top Songs &lt;year&gt;" playlist, each year weighted by recency. Ten years of Spotify's own measurement of what I actually played — the deepest evidence in the data, and the signal that gets my reference cases right unprompted. |
| Top tracks | `top` | 0.18 | How many of my 50 current top tracks are theirs. Spotify returns a short-term window, so this is the only signal that reflects *now*. Weighted to keep the chart moving between wraps. |
| Playlist spread | `spread` | 0.16 | How many *different* playlists hold two or more of their tracks. One track in a 646-track bucket is not evidence of anything. |
| Playlist tracks | `tracks` | 0.10 | Total track credits across my playlists. Deliberately below `spread` and `top`: a big back catalogue is not the same as a favourite. |
| Favourites playlist | `FAV` | 0.12 | Whether they are in the playlist I keep by hand. The one place I can tell the ranking something the data does not record. |
| Dedicated playlist | `ded` | 0.09 | Whether more than half of a playlist of five or more tracks is theirs. |
| Followed | `fol` | 0.07 | Deliberate, but binary and cheap: you follow once and forget. |
| Recording activity | `rel3y` | 0.03 | New albums and singles over three years, reissues excluded. Nearly off — see below. |
| All-time top songs | `alltime` | 0.00 | Off. Spotify does not keep it current — two readings a day apart returned an identical snapshot id, and `history/alltime_snapshots.csv` watches whether that ever changes. The yearly wraps say the same thing with dates attached, so this is exported but not scored. |
| Liked tracks | `liked` | 0.00 | Off. I rarely use the like button, so the count measured my indifference to a feature rather than my taste. Shown, not scored; raising the weight turns it back on. |

### The yearly wraps

Spotify mints a "Your Top Songs &lt;year&gt;" playlist per account per year. Ten of
them, 2016 to 2025, are about 1,000 tracks of Spotify's own measurement of what
I actually played — the thing the weekly `top_tracks` snapshot would take years
to accumulate.

`yearly_artists.sh` finds them **by name**, not by stored id: any playlist owned
by Spotify called exactly `Your Top Songs <year>`. Nothing has to be configured,
no personal playlist id is committed, and a year saved later — a 2026 wrap next
December, or an older one backfilled — is picked up by the next run on its own.

Each year's tracks are weighted by recency, halving every `half_life_years` in
`yearly_weights.json`:

```json
{ "half_life_years": 3 }
```

At a half-life of 3 the newest wrap counts 1.00, three years back 0.50, and 2016
0.13. Without the decay a long-abandoned favourite outvotes what I actually
listen to now, which is the same failure the Best Of playlists caused. Raise the
half-life for a career retrospective; lower it for something closer to recent
taste.

### Reading the output

`favourite_artists.md` is formatted for reading and `favourite_artists.json`
holds the same rows as data. The page and the history series read the JSON:
parsing fixed-width columns broke silently the first time a signal was added,
with the new column absorbed into the artist name.

The figures are the raw measurements, not the scored ones. Two things they do not show:

**Counts are square-rooted and divided by the column maximum** before being
weighted, so 1 to 4 tracks moves the score far more than 46 to 49.

**Credits include featured artists and remixers.** A remix of someone else's
track counts for both of them.

`spread` and `tracks` are decimals because each playlist contributes its own
weight rather than a flat 1. `fol`, `ded` and `FAV` are flags. `rel3y` runs 0 to
1. A `0.00` means the artist has released nothing new in three years — every
ranked artist has a discography on disk, so it is a measurement rather than a
gap.

Three decisions matter more than the weights:

**A dedicated playlist counts for a lot.** An artist who is more than half of a
playlist of five or more tracks gets the `dedicated` flag. I have thirteen such
playlists, mostly named `BO <artist>`, and building one is a clearer statement
than any number of likes. Detection is by share, not by the naming convention,
so it keeps working if I stop using the `BO` prefix. Size does not grade it: a
six-track Best Of says as much as a forty-track one.

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
{ "yearly": 0.25, "top": 0.18, "spread": 0.16, "favourite": 0.12,
  "tracks": 0.10, "dedicated": 0.09, "followed": 0.07,
  "activity": 0.03, "alltime": 0.00, "liked": 0.00 }
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
appear at all, absent any other signal. Without a floor the ranking is mostly
noise: most artists in my playlists appear exactly once. After the zero-weighted
playlists and that floor, 482 artists are ranked.

### The favourites playlist

One playlist is flagged `"favourites": true` in `playlist_weights.json`, and the
artists on it score for it. It is the only route by which I can tell the ranking
something my listening does not record — King Buffalo have been my favourite
band for years, tour constantly, and have ten deliberately-placed tracks and no
studio album since 2021, so nothing else in this data knows it.

At 0.15 it lifts an artist who already has other evidence rather than carrying
one alone: an artist present *only* through it lands around 90th. Raising the
weight, or making it a floor rather than an addition, would change that.

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

It exists because playlists are not equal evidence. Two Discover Weekly
archives held 65% of all tracks and 73% of all artists — Spotify recommending
to me, never a choice I made — and weigh nothing. Nor do event playlists, other
people's taste, or a running playlist I have not opened in years, since Spotify
exposes no date to decay it by.

`Starred` and `Liked from Radio` are legacy but keep full weight; they record
real choices, just old ones, and want a cleanup rather than a discount.

## The time series

`history/rankings.csv` gains the top fifty every week, one row per artist:

```
date,rank,artist,score,top,spread,tracks,followed,dedicated,favourite,activity,weights
2026-10-30,1,"ZZ Top",79.8,1,5.0,49.0,y,y,Y,0.50,271ea7e7
```

Every signal is stored beside the score, so a movement can be attributed rather
than merely observed — an artist climbing on `top` is a different event from one
climbing because a playlist grew.

**The last column is a hash of the weights that produced the score.** A score is
only meaningful relative to the weights behind it, so when that hash changes the
series has a discontinuity rather than a trend, and anything spanning the change
is comparing two different measures. This is why the weights are fixed.

Re-running on the same day replaces that day's rows rather than appending
duplicates, so a manual run between scheduled ones costs nothing. `HISTORY_DATE`
overrides the date and `HISTORY_DEPTH` the fifty.

CSV because it outlives whatever plots it: a spreadsheet, a notebook, or
something not yet written.

## Finding music I do not know

Each cached artist carries twenty `related_artists` from Spotify. Across 463
artists that is some nine thousand edges, and the ones worth reading are those
my highest-scoring artists point at.

`discover_artists.sh` collects every edge, drops any artist already anywhere in
my data, and scores the rest by the summed favourite-score of whoever
recommended them — so a nod from my third-ranked artist outweighs one from my
three hundredth. It makes no API calls; the edges are already on disk.

**It cannot tell a find from a household name.** The CLI exposes no popularity
or follower count, so an artist I obviously know but have never saved looks
exactly like a discovery — Led Zeppelin and AC/DC both placed in the first
twenty. Vote counts do not separate them either. `discover_exclude.txt` is the
fix, one name per line, maintained by hand.

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
