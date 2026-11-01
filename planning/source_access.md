# Building the gig adapters without reaching the sources

Written 1 November 2026. Claude's cloud workspace, where most of this repo's
code gets written, runs behind an allowlist and cannot reach sydneymusic.net or
app.ticketmaster.com. The laptop can. These are the ways to build the two
adapters anyway, and what each costs. Not mutually exclusive: the suggested
order is at the end.

## 1. Allow both domains for Claude's workspace

Add `sydneymusic.net` and `app.ticketmaster.com` to the allowed domains in
claude.ai (in a browser: Settings > Capabilities).

**For**
- The SydneyMusic parser is written against the real HTML and tested against
  the real page, so the first run on the laptop is not the first time it meets
  the site.
- Both adapters can be run end to end in the workspace, including the
  month-by-month Ticketmaster paging and the de-duplication between the two.
- Later fixes, when SydneyMusic changes its layout, can be diagnosed and tested
  from a chat on the phone rather than at the laptop.

**Against**
- Testing Ticketmaster in the workspace needs the API key there too, pasted once
  per session. It is never written to the repo, but it does pass through a chat.
- It widens what the workspace can reach. Two named sites is a small widening;
  it still applies to every session, not just this project.
- The workspace's IP is a datacentre address, so it tells us nothing about how
  SydneyMusic treats the laptop's home connection (that is probably better, not
  worse).

## 2. Attach a saved copy of the page

Save `https://sydneymusic.net/gig-guide` from Safari on the laptop (File > Save
As, Page Source) and attach it in the chat.

**For**
- No settings change and no key in the chat.
- The parser is still written against real HTML, and the saved page becomes a
  test fixture in the repo, so a future layout change can be compared against a
  known-good copy.

**Against**
- Only SydneyMusic. The Ticketmaster adapter is written from the documented
  response shape and is first run for real on the laptop.
- A snapshot: if the page is assembled partly by JavaScript, the saved source
  may not match what the scraper fetches. Worth checking when the file arrives.
- Each layout change later means another save and attach.

## 3. Build everything that does not need the sources, now

The adapter framework and merge, Spotify matching, scoring, the page section,
the Gig Scouting playlist and the calendar files, tested against invented gigs
in the shared format. The two real adapters are added afterwards.

**For**
- Most of the work is downstream of the adapters and does not care where gigs
  come from, which is the point of the shared format. It can all be built and
  tested today.
- Writing the fixtures first pins the shared format down before either adapter
  exists, which keeps the adapters honest.

**Against**
- Matching and scoring are tested on invented names, not on what SydneyMusic
  actually lists ("Tommy Brooks W/ Leroy Lee", country tags, DJ sets). Some of
  that parsing will need revisiting against real listings.
- Nothing is usable until 1 or 2 also happens.

## Suggested order

Start with 3, since it is useful whatever happens next. Then 1 if allowing the
domains is acceptable, otherwise 2 for SydneyMusic, with Ticketmaster written
from its documentation and checked on the laptop.
