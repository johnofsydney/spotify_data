"""Act-name normalisation shared by merging, matching and scoring."""

import re
import unicodedata

# "(USA)", "(PAK/USA)", "(DJ set)", "(live)": billing decoration, not the name.
_DECORATION = re.compile(
    r"\s*\((?:[A-Z]{2,3}(?:\s*/\s*[A-Z]{2,3})*|DJ set|DJ|live|live set|album launch|"
    r"single launch|ep launch|solo|duo|trio|band|full band)\)\s*", re.I)


def clean(name):
    """The act's name as it would appear on Spotify. Also drops "[DJ]",
    "[Live]" and other square-bracketed billing notes."""
    s = re.sub(r"\s*\[[^\]]*\]\s*", " ", name or "")
    return re.sub(r"\s+", " ", _DECORATION.sub(" ", s)).strip()


def norm(name):
    """Comparison key: decoration removed, accents folded, punctuation dropped,
    a leading "the" ignored. "The Church (AUS)" and "church" compare equal."""
    s = unicodedata.normalize("NFKD", clean(name).replace("ı", "i").replace("ø", "o").replace("Ø", "O")).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", " ", s.lower().replace("&", " and ")).strip()
    return re.sub(r"^the ", "", s)


def slug(name):
    return re.sub(r"\s+", "-", norm(name))[:60] or "gig"
