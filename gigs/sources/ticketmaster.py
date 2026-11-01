#!/usr/bin/env python3
"""Ticketmaster Discovery API adapter: music events around the inner city.

Config (this source's block of gigs.json): latlong, radius_km, months. The key
comes from TICKETMASTER_API_KEY in the environment (.env), never from config.

The API will not page past the 1,000th result of a query (size × page < 1000),
so the window is queried a month at a time, which keeps every query well under
that. Free keys allow 5 requests a second; a short pause keeps under it.
"""

import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import gigshape  # noqa: E402

SOURCE = "ticketmaster"
ENDPOINT = "https://app.ticketmaster.com/discovery/v2/events.json"
PAGE_SIZE = 200


def months(start, n):
    """[start, +1 month), [+1, +2) … as aware UTC datetimes."""
    edges = [start]
    y, m = start.year, start.month
    for _ in range(n):
        m += 1
        if m > 12:
            y, m = y + 1, 1
        edges.append(datetime.datetime(y, m, 1, tzinfo=datetime.timezone.utc))
    return list(zip(edges, edges[1:]))


def query(key, params):
    url = ENDPOINT + "?" + urllib.parse.urlencode({**params, "apikey": key})
    for attempt in range(5):
        try:
            return json.loads(gigshape.fetch(url))
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                time.sleep(2 ** attempt)
                continue
            raise


def to_gig(e):
    start = e.get("dates", {}).get("start", {})
    if start.get("dateTBD") or start.get("dateTBA") or not start.get("localDate"):
        return None
    if e.get("dates", {}).get("status", {}).get("code") in ("cancelled", "offsale"):
        return None
    venues = e.get("_embedded", {}).get("venues") or [{}]
    v = venues[0]
    # localDate and localTime are the venue's wall clock; attach Sydney's offset
    # for that date so the timestamp is unambiguous.
    local = start["localDate"] + "T" + (start.get("localTime") or "20:00:00")
    naive = datetime.datetime.fromisoformat(local)
    offset = sydney_offset(naive)
    iso = naive.replace(tzinfo=datetime.timezone(offset)).isoformat()
    attractions = e.get("_embedded", {}).get("attractions") or []
    names = [a.get("name") for a in attractions if a.get("name")] or [e.get("name")]
    acts = [{"name": n, "billing": "headline" if i == 0 else "support"} for i, n in enumerate(names)]
    address = ", ".join(x for x in [v.get("address", {}).get("line1"), v.get("city", {}).get("name")] if x)
    return gigshape.gig(SOURCE, e["id"], iso, v.get("name") or "", acts,
                        venue_id=v.get("id"), address=address or None,
                        suburb=v.get("city", {}).get("name"), url=e.get("url"),
                        title=e.get("name"))


def sydney_offset(naive):
    """AEDT (+11) from the first Sunday of October to the first Sunday of April,
    AEST (+10) otherwise. Avoids needing zoneinfo data on the machine."""
    def first_sunday(y, m):
        d = datetime.date(y, m, 1)
        return d + datetime.timedelta(days=(6 - d.weekday()) % 7)
    d = naive.date()
    dst = d >= first_sunday(d.year, 10) or d < first_sunday(d.year, 4)
    return datetime.timedelta(hours=11 if dst else 10)


def main():
    cfg = gigshape.config()
    key = os.environ.get("TICKETMASTER_API_KEY")
    if not key:
        raise SystemExit("ticketmaster: TICKETMASTER_API_KEY not set (see .env.example)")
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    seen, gigs, calls = set(), [], 0
    for lo, hi in months(now, int(cfg.get("months", 12))):
        page = 0
        while True:
            data = query(key, {
                "latlong": cfg.get("latlong", "-33.886,151.211"),
                "radius": cfg.get("radius_km", 8), "unit": "km",
                "classificationName": "music", "countryCode": "AU",
                "startDateTime": lo.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "endDateTime": hi.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "size": PAGE_SIZE, "page": page, "sort": "date,asc",
            })
            calls += 1
            time.sleep(0.25)
            for e in data.get("_embedded", {}).get("events", []):
                g = to_gig(e)
                if g and g["source_id"] not in seen:
                    seen.add(g["source_id"])
                    gigs.append(g)
            total = data.get("page", {}).get("totalPages", 0)
            page += 1
            if page >= total or page * PAGE_SIZE >= 1000:
                if page < total:
                    print(f"ticketmaster: {lo:%Y-%m} has more than 1000 events, rest skipped",
                          file=sys.stderr)
                break
    print(f"ticketmaster: {len(gigs)} events in {calls} calls", file=sys.stderr)
    gigshape.emit(gigs)


if __name__ == "__main__":
    main()
