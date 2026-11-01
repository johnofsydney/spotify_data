#!/usr/bin/env python3
"""One .ics file per recommended gig, into docs/gigs/, served by GitHub Pages.

The page links each gig to its file; on an iPhone, tapping one opens the
add-to-calendar sheet. Neither source gives an end time, so events last
duration_hours (3). The folder is rewritten every run, so past gigs' files go.
"""

import datetime
import glob
import json
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(root, "docs", "gigs")
HOURS = json.load(open(os.path.join(root, "gigs.json"))).get("calendar", {}).get("duration_hours", 3)


def esc(s):
    return (s or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def fold(line):
    """iCalendar lines are at most 75 octets; continuations start with a space."""
    out, cur = [], b""
    for ch in line:
        b = ch.encode("utf-8")
        if len(cur) + len(b) > (75 if not out else 74):
            out.append(cur.decode("utf-8"))
            cur = b""
        cur += b
    out.append(cur.decode("utf-8"))
    return "\r\n ".join(out)


def utc(dt):
    return dt.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def ics(g, stamp):
    start = datetime.datetime.fromisoformat(g["start"])
    lineup = " / ".join(a["name"] for a in g["acts"])
    link = next((l["url"] for l in g["links"] if l.get("url")), None)
    why = [f"{a['name']}: favourite #{a['rank']}" if a.get("rank") else
           f"{a['name']}: like {', '.join(a['via'])}"
           for a in g["acts"] if a.get("score", 0) >= 1 and (a.get("rank") or a.get("via"))]
    desc = lineup + ("\n\n" + "\n".join(why) if why else "") + (f"\n\n{link}" if link else "")
    lines = [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spotify_data//gig picker//EN",
        "CALSCALE:GREGORIAN", "BEGIN:VEVENT",
        f"UID:{g['key']}@spotify_data",
        f"DTSTAMP:{stamp}",
        f"DTSTART:{utc(start)}",
        f"DTEND:{utc(start + datetime.timedelta(hours=HOURS))}",
        f"SUMMARY:{esc(lineup)}",
        f"LOCATION:{esc(', '.join(x for x in [g['venue'], g.get('address')] if x))}",
        f"DESCRIPTION:{esc(desc)}",
    ]
    if link:
        lines.append(f"URL:{link}")
    lines += ["END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(fold(l) for l in lines) + "\r\n"


def main():
    recs = json.load(open(os.path.join(root, "gig_recs.json")))
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, "*.ics")):
        os.remove(old)
    stamp = utc(datetime.datetime.now(datetime.timezone.utc))
    written = set()
    for section in ("new", "coming", "later"):
        for g in recs[section]:
            if g["key"] in written:
                continue
            with open(os.path.join(OUT, g["key"] + ".ics"), "w", encoding="utf-8", newline="") as f:
                f.write(ics(g, stamp))
            written.add(g["key"])
    print(f"calendar: {len(written)} files -> docs/gigs/")


if __name__ == "__main__":
    main()
