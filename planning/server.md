# Should this run on a server?

Written 1 November 2026, for future consideration. No decision taken: it runs
on the laptop today.

## How it runs now

launchd on a MacBook, Mondays at 11:00. `refresh.sh` calls `spotify_player` for
every export, scores everything offline with bash and jq, commits, and pushes;
GitHub Pages serves `docs/`. The gig picker will add two outbound sources
(SydneyMusic.net, scraped; Ticketmaster, an API key).

## For moving it

- **Runs on time, every time.** The README already names the cost of the
  laptop: launchd fires once on wake however many Mondays were missed, so a
  fortnight away loses a top-tracks snapshot that nothing can recover. A server
  never misses one, and the time series is the point of the weekly run.
- **More frequent checks become free.** A daily Ticketmaster check for
  favourites, already listed as the likely refinement, is a cron line rather than
  a laptop that has to be awake.
- **Alerts get easier.** Email or a push notification from a machine that is
  always on is simpler than from a laptop that may be shut.
- **The laptop is no longer the system.** A lost, replaced or wiped laptop stops
  everything until the setup in the README is repeated.

## Against moving it

- **Spotify login is interactive.** `spotify_player authenticate` needs a browser.
  On a server that means logging in on the laptop and copying the cached tokens
  (`user_client_token.json`, `credentials.json`) across, then trusting refresh to
  keep them alive. If the token is ever revoked, the fix is a manual round trip.
- **Shared client id, shared limits.** `spotify_player` uses a bundled client id
  shared by many users. It works from a home connection today; from a
  datacentre address it is untested and could hit rate limits sooner.
- **Scraping from a datacentre.** Some sites block or challenge cloud IP ranges.
  SydneyMusic may never notice one request a week, but it is a new failure mode
  that a home connection does not have.
- **Secrets move off the laptop.** `.env` values, the Spotify tokens and a GitHub
  credential that can push all have to live on the server or in a secrets store.
- **Upkeep.** OS updates, a Linux build of `spotify_player`, disk, logs and
  noticing when it has quietly stopped. The laptop gets that attention for free
  because it is used every day.
- **Debugging is further away.** Today a failed run is a terminal and
  `.refresh.log` on the machine in front of you.
- **It works.** The laptop's real cost is the occasional missed snapshot.

## The options, if it moves

| Option | Cost | Fit | Main catch |
| --- | --- | --- | --- |
| **GitHub Actions, scheduled workflow** | Free for a public repo | Closest fit: the repo is already the database and Pages the output, so the job is "check out, run, push" | Spotify tokens as repository secrets, and if Spotify rotates the refresh token the workflow must write the new one back (needs a token with secrets access). Datacentre IP for scraping. Scheduled runs can be delayed at busy times, which suits a weekly job fine |
| **Raspberry Pi or old Mac at home** | About $100 one-off, or nothing | Same as the laptop, minus the sleeping; home IP, so scraping and Spotify behave exactly as now | Another box to keep alive and updated; power and network outages at home |
| **Small VPS** (e.g. a $5–6 a month droplet) | $60–75 a year | Always on, full control, cron, easy to SSH into | Datacentre IP, and all of the upkeep with none of the convenience of Actions |

## Suggested path, when the time comes

1. Stay on the laptop until missed snapshots or the wish for daily checks
   actually hurts.
2. Try GitHub Actions first. Everything else is already there. The one thing to
   prove is that the copied Spotify tokens keep refreshing headlessly for a few
   weeks; run it alongside the laptop, writing to a branch, until they do.
3. If Actions trips over the tokens or a blocked scrape, a Pi at home keeps
   the always-on part and the home IP, at the cost of a box to look after.

Either way the scripts barely change: they already run from any checkout,
read their settings from `.env`, and log to stdout. What needs adding is a
headless way to seed `spotify_player`'s tokens and a non-macOS scheduler in
place of `setup/install-schedule.sh`.
