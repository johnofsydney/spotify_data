#!/usr/bin/env python3
"""SydneyMusic.net adapter: the whole gig guide as shared-shape gigs on stdout.

Two backends behind one entry point, chosen by "mode" in this source's block of
gigs.json:

  scrape  fetch https://sydneymusic.net/gig-guide (one page, about two months)
          and parse it. The default, and the only one that exists today.
  api     their licensed API. Not written: when access is granted, implement
          from_api() to return the same shape and flip "mode". Nothing
          downstream changes.

Optional "html_file" parses a saved copy instead of fetching, for fixing the
parser against a known page without hitting the site.
"""

import datetime
import html
import os
import re
import sys
import urllib.parse
from html.parser import HTMLParser

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import gigshape  # noqa: E402

BASE = "https://sydneymusic.net"
SOURCE = "sydneymusic"


class GuideParser(HTMLParser):
    """Collects one dict per event card. The page is server-rendered by
    SvelteKit with stable class names: each card has a div carrying data-gigid
    and data-gigstartdate, then h4.headliner, p.supports ("W/ a, b"),
    span.time, a.venue (href /gig-guide/venues/<slug>), a.moreinfo,
    a.addtocalendar (a data: URL holding an iCalendar event, the only place the
    venue's street address appears) and a FREE pill."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.cards = []
        self.card = None
        self.field = None
        self.depth = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        if "data-gigid" in a:
            self.card = {"id": a["data-gigid"], "start": a.get("data-gigstartdate"),
                         "headliner": "", "supports": "", "venue": "", "free": False}
            self.cards.append(self.card)
            return
        if self.card is None:
            return
        if tag == "h4" and "headliner" in cls:
            self.field = "headliner"
        elif tag == "p" and "supports" in cls:
            self.field = "supports"
        elif tag == "a" and "venue" in cls:
            self.field = "venue"
            self.card["venue_href"] = a.get("href")
        elif tag == "a" and "moreinfo" in cls:
            self.card["url"] = a.get("href")
        elif tag == "a" and "addtocalendar" in cls:
            self.card["ics"] = a.get("href")
        elif tag == "div" and "bg-pill" in cls:
            self.field = "pill"

    def handle_endtag(self, tag):
        if self.field and tag in ("h4", "p", "a", "div"):
            self.field = None

    def handle_data(self, data):
        if self.card is None or not self.field:
            return
        if self.field == "pill":
            if data.strip().upper() == "FREE":
                self.card["free"] = True
            return
        self.card[self.field] += data


def ics_location(href):
    """LOCATION from the card's data:text/calendar link: 'Venue, street, suburb'."""
    if not href or not href.startswith("data:text/calendar"):
        return None
    text = urllib.parse.unquote(href.split(",", 1)[1])
    text = re.sub(r"\r?\n[ \t]", "", text)  # unfold continuation lines
    m = re.search(r"^LOCATION:(.*)$", text, re.M)
    if not m:
        return None
    # iCalendar escapes the commas inside a value, so "\\," separates the parts.
    return [p.strip() for p in m.group(1).strip().split("\\,")]


def suburb_of(parts):
    if not parts or len(parts) < 2:
        return None, None
    parts = [p.replace("\\;", ";").replace("\\n", " ") for p in parts]
    suburb = re.sub(r"\s+(NSW|New South Wales)?\s*\d{4}$", "", parts[-1]).strip()
    suburb = re.sub(r"\s+NSW$", "", suburb).strip()
    return ", ".join(parts[1:]), suburb or None


def split_acts(headliner, supports):
    acts = [{"name": headliner.strip(), "billing": "headline"}]
    s = re.sub(r"^\s*W/\s*", "", supports.strip(), flags=re.I)
    for name in re.split(r"\s*,\s*", s) if s else []:
        name = name.strip()
        if name and not re.fullmatch(r"(and |\+ ?)?(more|guests|special guests|tba|tbc)", name, re.I):
            acts.append({"name": name, "billing": "support"})
    return acts


def start_iso(raw):
    """'Sun Nov 01 2026 13:00:00 GMT+1100 (Australian Eastern Daylight Time)'"""
    raw = re.sub(r"\s*\(.*\)$", "", raw or "")
    return datetime.datetime.strptime(raw, "%a %b %d %Y %H:%M:%S GMT%z").isoformat()


def from_scrape(cfg):
    if cfg.get("html_file"):
        with open(cfg["html_file"], encoding="utf-8") as f:
            page = f.read()
    else:
        page = gigshape.fetch(cfg.get("url", BASE + "/gig-guide"))
        raw_dir = cfg.get("raw_dir")
        if raw_dir:
            os.makedirs(raw_dir, exist_ok=True)
            with open(os.path.join(raw_dir, "sydneymusic.html"), "w", encoding="utf-8") as f:
                f.write(page)
    p = GuideParser()
    p.feed(page)
    gigs = []
    for c in p.cards:
        if not c["headliner"].strip() or not c.get("start"):
            continue
        address, suburb = suburb_of(ics_location(c.get("ics")))
        href = c.get("venue_href") or ""
        gigs.append(gigshape.gig(
            SOURCE, c["id"], start_iso(c["start"]), html.unescape(c["venue"]).strip(),
            split_acts(c["headliner"], c["supports"]),
            venue_id=href.rsplit("/", 1)[-1] or None, address=address, suburb=suburb,
            url=c.get("url") or (BASE + href if href else None), free=c["free"],
            title=c["headliner"].strip()))
    return gigs


def from_api(cfg):
    raise SystemExit("sydneymusic: mode 'api' is not written yet; set mode to 'scrape'")


if __name__ == "__main__":
    cfg = gigshape.config()
    mode = cfg.get("mode", "scrape")
    backends = {"scrape": from_scrape, "api": from_api}
    if mode not in backends:
        raise SystemExit(f"sydneymusic: unknown mode '{mode}'")
    gigshape.emit(backends[mode](cfg))
