# Open questions and things to revisit

A running list. Decisions that are settled live in [gigs.md](gigs.md); this file
is what is still undecided, and what was decided "for now" with a note to adapt
later. Strike an item through, or move it into the design, once it is settled.

## Open questions

### Gigs
- **Output (stage 5).** Not discussed yet. A section on the page is assumed; a
  playlist of the coming-up bands and calendar entries are possible extras.
- **Getting at SydneyMusic's HTML.** Claude's workspace cannot reach
  sydneymusic.net, so the parser cannot be written or tested there. Either allow
  the domain in claude.ai (Settings > Capabilities) or attach a saved copy of
  `https://sydneymusic.net/gig-guide`.
- **Ticketmaster API key.** Register at developer.ticketmaster.com and put it in
  `.env` as `TICKETMASTER_API_KEY`.
- **The "inner city" radius.** Inner west and eastern suburbs only. Ticketmaster
  searches a circle, which that area is not, so the centre and radius need
  picking, with the venue exclusion list trimming whatever the circle catches
  that it should not.
- **The cut-offs.** "Top 100 favourites" for new announcements and a minimum
  gig score for coming up and further out were proposals, not tuned numbers.
- **Python for the adapters.** Proposed (standard library only, so nothing to
  install) because parsing HTML in bash and jq is fragile. Not explicitly agreed.

## Decided for now, adapt later

### Gigs
- **Weekly checks.** New announcements are found by the Monday refresh. A
  separate daily Ticketmaster check for favourites is the likely refinement if a
  presale is ever missed.
- **Alerts are a page section only.** Email, a macOS notification or a phone
  reminder are the options if the page turns out not to be looked at often
  enough.
- **Guessed Spotify matches score × 0.7.** When a gig act's name matches several
  Spotify artists, the best guess is used, marked as a guess, and discounted.
- **"No data" gigs are a collapsed list.** Acts Spotify cannot place, shown
  under the ranked gigs rather than scored as zero or hidden.

## Concepts to implement later

### Exclude lists, one per purpose
Exclusions are currently one file, `discover_exclude.txt` (household names kept
off the discovery list), plus the album club, which is a playlist rather than a
file. The idea is a family of plain-text lists, one per purpose, in one place,
same format as today: one name per line, matched exactly, `#` for comments.

- `exclude/discovery_artists.txt` — artists kept off the discovery list and
  playlist. `discover_exclude.txt` moves here.
- `exclude/gig_venues.txt` — venues the gig picker drops, e.g. anything outside
  the inner west and eastern suburbs.
- Likely later: `exclude/gig_artists.txt` (acts I never want suggested live),
  `exclude/albums.txt` (individual albums, alongside the album club playlist).

Each consumer reads only its own list, so adding one never changes another.
