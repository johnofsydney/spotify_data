#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/index.html"
top_n="${PAGE_TOP:-50}"
disc_n="${PAGE_DISCOVER:-50}"

favs=$(jq -c --argjson n "$top_n" '[.artists[0:$n][] |
  {rank, score, name, yearly, years: .yearly_years, top, spread, tracks,
   fol: (if .followed then "y" else "n" end),
   ded: (if .dedicated then "y" else "n" end),
   fav: (if .favourite then "Y" else "-" end),
   act: .activity}]' "$root/favourite_artists.json")

# The breakdown reads the points favourite_artists.sh scored, rather than
# recomputing them, so the page cannot disagree with the ranking.
brk=$(jq -c --argjson n "$top_n" '[.artists[0:$n][] |
  {rank, score, name, points, yearly, years: .yearly_years, top, spread, tracks,
   followed, dedicated, favourite, activity}]' "$root/favourite_artists.json")
tuning=$(jq -c '.config.tuning // {}' "$root/favourite_artists.json")
# One-line stories from bin/artist_stories.py, for the breakdown's last column.
stories=$( [ -f "$root/artist_stories.json" ] &&
  jq -c --slurpfile f "$root/favourite_artists.json" --argjson n "$top_n" \
    '. as $s | [$f[0].artists[0:$n][].name] | map({key: ., value: $s[.]}) | map(select(.value)) | from_entries' \
    "$root/artist_stories.json" || echo '{}')
weights=$(jq -c '.config.weights | ([.[]] | add) as $s | map_values(if $s > 1.5 then . / 100 else . end)' "$root/favourite_artists.json")

disc=$(jq -c --argjson n "$disc_n" '[.[0:$n][] |
  {rank, score, votes, name, from: (.from | join(", "))}]' "$root/discover_artists.json")

albums=$( [ -f "$root/album_pool.json" ] && jq -c '[.[] | {k: .key, a: .artist_id, artist, album, id, year, source, hits, new, score, from: (.from | join(", "))}]' "$root/album_pool.json" || echo '[]')
# Gigs: the scored sections in full, the no-data list trimmed to what the
# collapsed list shows. Absent until the first gig run.
gigs=$( [ -f "$root/gig_recs.json" ] && jq -c '
  def slim: {key, date, time, venue, suburb, free, score, new,
             link: ([.links[]?.url | select(.)] | first),
             acts: [.acts[] | {name, id, kind, score, rank, via, guess, billing}]};
  {generated, pending_acts, listed,
   new: [.new[] | slim], coming: [.coming[] | slim], later: [.later[] | slim],
   nodata: [.nodata[] | {key, date, time, venue, free,
                         link: ([.links[]?.url | select(.)] | first),
                         acts: [.acts[].name]}]}' "$root/gig_recs.json" || echo 'null')

per_artist=$(jq -r '.per_artist // 1' "$root/albums.json" 2>/dev/null || echo 1)
album_count=$(jq -r '.count // 20' "$root/albums.json" 2>/dev/null || echo 20)

# Every artist on the album club playlist, for tinting their rows in every
# table. Found by name in playlist_weights.json, like album_recs.sh does.
club_name=$(jq -r '.exclude_playlist // "Elderly Gents Album Club"' "$root/albums.json" 2>/dev/null || echo "Elderly Gents Album Club")
club_id=$(jq -r --arg n "$club_name" 'to_entries[] | select(.value.name == $n) | .key' "$root/playlist_weights.json" | head -1)
club=$( [ -n "$club_id" ] && [ -f "$root/cache/playlists/$club_id.json" ] &&
  jq -c '[.tracks[].artists[].name] | unique' "$root/cache/playlists/$club_id.json" || echo '[]')

# Spotify ids by artist name, for linking names in every table to the artist's
# page. Known artists come from their cached details, discovery artists from the
# discovery list; gig acts carry their own ids.
artist_ids=$( { jq -s '[.[] | .artist | select(.id) | {key: .name, value: .id}]' "$root"/cache/artists/*.json
  jq '[.[] | select(.id) | {key: .name, value: .id}]' "$root/discover_artists.json"; } |
  jq -s -c 'add | from_entries')

# Weekly positions from history/rankings.csv: every run date, the weights stamp
# each was scored with, and each artist's rank per date (null when outside the
# top 50 that week). Feeds the trend on each favourites row and the chart.
history=$(python3 - "$root/history/rankings.csv" <<'PY'
import csv, json, sys, os
path = sys.argv[1]
if not os.path.exists(path):
    print('{"dates":[],"weights":[],"ranks":{}}'); sys.exit()
rows = list(csv.DictReader(open(path, encoding="utf-8")))
dates = sorted({r["date"] for r in rows})
idx = {d: i for i, d in enumerate(dates)}
weights = {r["date"]: r.get("weights", "") for r in rows}
ranks = {}
for r in rows:
    ranks.setdefault(r["artist"], [None] * len(dates))[idx[r["date"]]] = int(r["rank"])
print(json.dumps({"dates": dates, "weights": [weights[d] for d in dates], "ranks": ranks},
                 separators=(",", ":"), ensure_ascii=False))
PY
)

generated=$(date '+%-d %B %Y')
snapshots=$(awk -F',' 'NR>1 {print $1}' "$root/history/rankings.csv" 2>/dev/null | sort -u | wc -l | tr -d ' ')

cat > "$out" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Listening</title>
<style>
:root {
  --bg: #fbfaf8; --fg: #1a1a18; --muted: #6b6a66; --line: #e4e1db;
  --card: #ffffff; --accent: #7a5c3e; --chip: #f0ece5;
}
:root:not([data-theme="light"]) { }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #15140f; --fg: #eceae4; --muted: #99958c; --line: #2c2a24;
    --card: #1d1b16; --accent: #c9a37a; --chip: #27251f;
  }
}
:root[data-theme="dark"] {
  --bg: #15140f; --fg: #eceae4; --muted: #99958c; --line: #2c2a24;
  --card: #1d1b16; --accent: #c9a37a; --chip: #27251f;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.5 ui-sans-serif, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
  -webkit-text-size-adjust: 100%;
}
.wrap { max-width: 980px; margin: 0 auto; padding: 48px 16px 80px; }
header { margin-bottom: 40px; }
h1 { font-size: 30px; margin: 0 0 6px; letter-spacing: -0.02em; }
.sub { color: var(--muted); font-size: 14px; }
h2 { font-size: 20px; margin: 48px 0 6px; letter-spacing: -0.01em; }
h2:first-of-type { margin-top: 36px; }
.note { color: var(--muted); font-size: 14px; margin: 0 0 18px; max-width: 62ch; }
.list { border-top: 1px solid var(--line); }
.row {
  display: grid; grid-template-columns: 34px 1fr auto; gap: 12px;
  align-items: baseline; padding: 11px 4px; border-bottom: 1px solid var(--line);
}
.row:hover { background: var(--card); }
h3.subhead { font-size: 15px; margin: 28px 0 6px; }
.trend { display: flex; align-items: center; justify-content: flex-end; gap: 4px; margin-top: 3px;
  font-size: 11px; color: var(--muted); font-weight: 500; font-variant-numeric: tabular-nums; }
.trend svg { display: block; overflow: visible; }
.trend .up { color: var(--accent); }
.bump { position: relative; }
.bump svg { display: block; overflow: visible; font: 11px ui-sans-serif, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
.bump .grid { stroke: var(--line); stroke-width: 1; }
.bump .axis { fill: var(--muted); }
.bump .halo { paint-order: stroke; stroke: var(--bg); stroke-width: 4px; stroke-linejoin: round; }
.bump .wchange { stroke: var(--muted); stroke-dasharray: 3 3; stroke-width: 1; }
.bump .ln { fill: none; stroke: var(--muted); stroke-opacity: .45; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
.bump .pt { fill: var(--muted); fill-opacity: .55; stroke: var(--bg); stroke-width: 2; cursor: pointer; }
.bump .lbl { fill: var(--muted); cursor: pointer; }
.bump .hit { fill: none; stroke: transparent; stroke-width: 14; cursor: pointer; pointer-events: stroke; }
.bump .on .ln { stroke: var(--accent); stroke-opacity: 1; stroke-width: 2.5; }
.bump .on .pt { fill: var(--accent); fill-opacity: 1; }
.bump .on .lbl { fill: var(--fg); font-weight: 650; }
.bump .tip { position: absolute; pointer-events: none; background: var(--fg); color: var(--bg);
  font-size: 12px; padding: 4px 8px; border-radius: 6px; white-space: nowrap; transform: translate(-50%, -130%); }
a.artist { color: inherit; text-decoration: none; }
a.artist:hover { text-decoration: underline; text-decoration-color: var(--accent); }
.meta a.artist { border-bottom: 1px dotted var(--line); }
.note.todo { margin-top: 14px; color: var(--fg); }
.note.todo .rank { color: var(--muted); font-size: 12px; }
/* Rows with an artist from the album club playlist, in every table. */
:root { --club: #f5ecd9; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --club: #2e2719; } }
:root[data-theme="dark"] { --club: #2e2719; }
.row.club, .row.club:hover, .brk tr.club td.pin { background: var(--club); }
.brk tr.club td:not([style]) { background: var(--club); }
.clubkey { display: inline-block; width: 10px; height: 10px; border-radius: 2px;
  background: var(--club); border: 1px solid var(--line); vertical-align: -1px; margin-right: 4px; }
/* Heading explanations in the score breakdown. */
.toast { position: fixed; left: 50%; bottom: 20px; transform: translate(-50%, 12px);
  max-width: min(92vw, 460px); background: var(--fg); color: var(--bg); font-size: 13px;
  line-height: 1.45; padding: 11px 14px; border-radius: 10px; opacity: 0; pointer-events: none;
  transition: opacity .18s, transform .18s; z-index: 10; box-shadow: 0 6px 24px rgba(0,0,0,.18); }
.toast.on { opacity: 1; transform: translate(-50%, 0); pointer-events: auto; }
.toast b { display: block; margin-bottom: 2px; }
.rank { color: var(--muted); font-variant-numeric: tabular-nums; font-size: 14px; }
.name { font-weight: 550; }
.meta { color: var(--muted); font-size: 13px; margin-top: 3px; }
.name a { color: inherit; text-decoration: none; border-bottom: 1px solid var(--line); }
.albumbar { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; margin: 0 0 14px; }
.albumbar button {
  font: inherit; font-size: 14px; padding: 7px 14px; border-radius: 8px; cursor: pointer;
  border: 1px solid var(--line); background: var(--card); color: var(--fg);
}
.albumbar button:disabled { opacity: .5; cursor: default; }
.albumbar button.link { border: 0; background: none; color: var(--accent); padding: 7px 0; }
.score {
  font-variant-numeric: tabular-nums; color: var(--accent);
  font-size: 14px; font-weight: 600;
}
.gigs h3 { font-size: 15px; margin: 26px 0 8px; color: var(--muted); font-weight: 600;
  text-transform: uppercase; letter-spacing: .04em; }
.gigrow { grid-template-columns: 70px 1fr auto; }
.gigdate { font-size: 13px; color: var(--accent); text-decoration: none; line-height: 1.25;
  font-variant-numeric: tabular-nums; }
.gigdate b { display: block; font-size: 15px; color: var(--fg); }
.gigs .meta a, details.nodata a { color: inherit; text-decoration: none; border-bottom: 1px solid var(--line); }
.act-fav { font-weight: 650; }
.act-dim { color: var(--muted); font-weight: 400; }
details.nodata summary { cursor: pointer; color: var(--accent); font-size: 14px; margin: 18px 0 8px; }
details.nodata .row { grid-template-columns: 70px 1fr; padding: 7px 4px; font-size: 14px; }
.chip.guess { font-style: italic; }
.chip {
  display: inline-block; background: var(--chip); color: var(--muted);
  border-radius: 10px; padding: 1px 7px; font-size: 11px; margin-left: 6px;
  vertical-align: 1px; letter-spacing: 0.02em;
}
/* The breakdown is a reference table, not a list to read down: denser type,
   a grid, and a sideways scroll on a phone with rank and name pinned. */
/* A sticky header cannot stick to the page from inside a sideways-scrolling
   box, so the box scrolls both ways and the header sticks to its top. */
.tablewrap { overflow: auto; max-height: 80vh; -webkit-overflow-scrolling: touch;
  border-top: 1px solid var(--line); border-bottom: 1px solid var(--line); overscroll-behavior: contain; }
table.brk { border-collapse: collapse; font-size: 12px; line-height: 1.25; width: 100%; font-variant-numeric: tabular-nums; }
.brk th, .brk td { padding: 6px 7px; border-bottom: 1px solid var(--line); text-align: right; white-space: nowrap; vertical-align: top; }
.brk thead th { font-weight: 600; color: var(--muted); font-size: 11px; letter-spacing: 0.02em; vertical-align: bottom;
  position: sticky; top: 0; z-index: 2; background: var(--bg); border-bottom: 0; box-shadow: inset 0 -1px 0 var(--line); }
.brk thead th .w { display: block; font-weight: 400; color: var(--accent); }
.brk thead button { all: unset; cursor: pointer; display: block; width: 100%; text-align: inherit; }
.brk thead button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.brk thead th[aria-sort] { color: var(--fg); }
.brk thead .arrow { display: inline-block; width: 0.9em; text-align: center; color: var(--accent); }
.brk .pin { position: sticky; background: var(--bg); z-index: 1; text-align: left; }
.brk .pin.r { left: 0; width: 30px; min-width: 30px; color: var(--muted); }
.brk .pin.n { left: 30px; max-width: 150px; overflow: hidden; text-overflow: ellipsis; font-weight: 550; box-shadow: inset -1px 0 0 var(--line); }
.brk thead th.pin { z-index: 3; }
.brk td.story { white-space: normal; text-align: left; min-width: 240px; max-width: 320px; color: var(--fg); font-size: 12px; line-height: 1.4; }
.brk th.storyh { text-align: left; }
.brk td.story .arch { display: block; font-size: 10px; text-transform: uppercase; letter-spacing: .05em; color: var(--accent); font-weight: 600; margin-bottom: 2px; }
.brk thead th.pin.n { box-shadow: inset -1px 0 0 var(--line), inset 0 -1px 0 var(--line); }
.brk td.total { color: var(--accent); font-weight: 650; }
.brk td b { font-weight: 600; display: block; }
.brk td .raw { display: block; color: var(--muted); font-size: 10.5px; margin-top: 2px; }
.brk td.zero b { color: var(--muted); font-weight: 400; }
footer { margin-top: 56px; color: var(--muted); font-size: 13px; border-top: 1px solid var(--line); padding-top: 16px; }
@media (max-width: 560px) {
  .wrap { padding: 32px 16px 64px; }
  h1 { font-size: 25px; }
  .row { grid-template-columns: 28px 1fr auto; gap: 10px; }
}
</style>
</head>
<body>
<div class="wrap">
<header>
  <h1>Listening</h1>
  <div class="sub">Generated $generated &middot; $snapshots weekly snapshot(s) recorded</div>
  <div class="sub" id="clubkey" hidden><span class="clubkey"></span>Tinted rows include an artist from $club_name.</div>
</header>

<h2>Favourite artists</h2>
<p class="note">Scored across ten years of Spotify's yearly top songs, current top
tracks, playlist breadth and depth, a hand-kept favourites playlist, dedicated
playlists, follows and recent releases. Updated weekly.</p>
<div class="list" id="favs"></div>
<div id="bumpwrap" hidden>
<h3 class="subhead">The top 15 over time</h3>
<p class="note">Weekly position of today's top 15. Tap a name or a line to follow
one artist; a dashed line marks a change of weights, where positions jump for
reasons that are not listening. Below the floor means outside the top 50.</p>
<div id="bump" class="bump"></div>
</div>
<p class="note todo" id="unfollowed" hidden></p>

<h2>Worth investigating</h2>
<p class="note">Artists absent from my library, ranked by which of my favourites
Spotify says they resemble &mdash; a nod from a higher-ranked artist counts for
more. Household names I simply have not saved can still slip through.</p>
<div class="list" id="disc"></div>

<section id="gigsection" hidden>
<h2>Gigs</h2>
<p class="note">Inner west, eastern suburbs and the city, from SydneyMusic.net and
Ticketmaster. Each act scores on the favourites' scale: a favourite at their own
score, anyone else by which favourites Spotify says they resemble (up to 40).
A gig is its best act plus 0.3 of the next three. Tap the date to add it to your
calendar.</p>
<div id="gigs"></div>
</section>

<h2>Albums to hear in full</h2>
<p class="note">From favourites and from the discovery list, ranked by how much I
like the artist, how many of their top tracks the album holds, and whether it is
new. One per artist. Left out: the album club playlist, best ofs and live records,
and anything that has had four weeks on the list.</p>
<div class="albumbar"><button id="albumsNext" type="button">Show me twenty others</button>
<button id="albumsReset" type="button" class="link" hidden>Back to this week's list</button>
<span id="albumsState" class="sub"></span></div>
<div class="list" id="albums"></div>

<h2>Score breakdown</h2>
<p class="note">How each of the top fifty earns its score. In each cell the bold
figure is the points that signal contributes, out of the most it can give (under
the heading), and the small figure is the raw measurement. The points add up to
the score. Counts are square-rooted against the highest of any artist, so the
first few tracks earn far more than the fortieth. Tap a heading to sort by it
and see what it measures; tap again to reverse.</p>
<div class="tablewrap"><table class="brk" id="brk"></table></div>

<div class="toast" id="toast" role="status" aria-live="polite"></div>
<footer>Built from Spotify data by <code>bin/build_page.sh</code>.</footer>
</div>
<script>
const favs = $favs;
const disc = $disc;
const albumPool = $albums;
const albumPer = $per_artist, albumCount = $album_count, albumStamp = '$generated';
const brk = $brk;
const weights = $weights;
const tuning = $tuning;
const stories = $stories;
const clubNorm = s => String(s).toLowerCase().replace(/\s*[\(\[][^\)\]]*[\)\]]/g, '')
  .normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/&/g, ' and ')
  .replace(/[^a-z0-9]+/g, ' ').trim().replace(/^the /, '');
const clubSet = new Set($club.map(clubNorm));
const isClub = name => clubSet.has(clubNorm(name));
const clubCls = names => [].concat(names).some(isClub) ? ' club' : '';
if (clubSet.size) document.getElementById('clubkey').hidden = false;
const artistIds = $artist_ids;
const hist = $history;
// A small line of an artist's weekly rank (1 at the top), the last point
// marked, and the move since the previous run.
const trendHtml = name => {
  const r = hist.ranks[name];
  if (!r || hist.dates.length < 2) return '';
  const pts = r.slice(-12), n = pts.length, W = 54, H = 16;
  const x = i => n === 1 ? W : i * W / (n - 1);
  const y = v => (v === null ? 51 : v - 1) / 50 * H;
  let d = '', pen = false;
  pts.forEach((v, i) => { if (v === null) { pen = false; return; }
    d += (pen ? 'L' : 'M') + x(i).toFixed(1) + ' ' + y(v).toFixed(1); pen = true; });
  const last = pts[n - 1], prev = pts[n - 2];
  let mv = '';
  if (last !== null && prev === null) mv = '<span class="up">new</span>';
  else if (last !== null && prev !== null && prev !== last)
    mv = prev > last ? '<span class="up">↑' + (prev - last) + '</span>' : '↓' + (last - prev);
  return '<div class="trend" title="Weekly position, last ' + n + ' runs">' +
    '<svg width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + ' ' + H + '" aria-hidden="true">' +
    '<path d="' + d + '" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" opacity=".7"/>' +
    (last !== null ? '<circle cx="' + x(n - 1) + '" cy="' + y(last) + '" r="2.2" fill="var(--accent)"/>' : '') +
    '</svg>' + mv + '</div>';
};
// Names link straight into the Spotify app (spotify: URIs open the desktop app,
// and on a phone the app, after the browser asks), not the web player.
// An act without a known id (a gig act not looked up yet, or not matched)
// opens a Spotify search for its name instead, billing tags like "(USA)" or
// "[DJ]" removed.
const artistLink = (name, id) => {
  id = id || artistIds[name];
  if (id) return '<a class="artist" href="spotify:artist:' + id + '">' + esc(name) + '</a>';
  const q = String(name).replace(/\s*[\(\[][^\)\]]*[\)\]]/g, '').trim();
  return '<a class="artist search" href="spotify:search:' + encodeURIComponent(q) + '">' + esc(name) + '</a>';
};
const linkList = names => [].concat(names).map(n => artistLink(n)).join(', ');
const esc = s => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
document.getElementById('favs').innerHTML = favs.map(a => {
  const chips = [
    a.fav === 'Y' ? '<span class="chip">favourite</span>' : '',
    a.ded === 'y' ? '<span class="chip">best of</span>' : '',
    a.top > 0 ? '<span class="chip">playing now</span>' : '',
    a.years >= 3 ? '<span class="chip">long haul</span>' : '',
    a.act >= 0.75 ? '<span class="chip">active</span>' : ''
  ].join('');
  const bits = [];
  if (a.spread > 0) bits.push(a.spread + ' playlists');
  if (a.tracks > 0) bits.push(a.tracks + ' tracks');
  if (a.top > 0) bits.push(a.top + ' in top 50');
  if (a.years > 0) bits.push('top songs in ' + a.years + (a.years === 1 ? ' year' : ' years'));
  return '<div class="row' + clubCls(a.name) + '"><div class="rank">' + a.rank + '</div>' +
    '<div><div class="name">' + artistLink(a.name) + chips + '</div>' +
    '<div class="meta">' + bits.join(' &middot; ') + '</div></div>' +
    '<div class="score">' + a.score + trendHtml(a.name) + '</div></div>';
}).join('');
// The top 15 over time: every line muted, one highlighted at a time (no
// palette of fifteen hues). x is real time, so gaps between runs show as gaps.
(() => {
  if (hist.dates.length < 2) return;
  const top = favs.slice(0, 15).map(a => a.name).filter(n => hist.ranks[n]);
  if (!top.length) return;
  document.getElementById('bumpwrap').hidden = false;
  const box = document.getElementById('bump');
  let picked = null;
  // Drawn at the box's real width, so text stays 11px on a phone and on a
  // desktop alike; redrawn when the width changes.
  const draw = () => {
  const W = Math.max(320, Math.round(box.clientWidth || 640));
  const narrow = W < 520;
  const H = narrow ? 300 : 340, L = 26, R = narrow ? 118 : 170, T = 10, B = 24;
  const t = hist.dates.map(d => new Date(d + 'T00:00:00').getTime());
  const t0 = t[0], t1 = t[t.length - 1];
  const X = ms => L + (t1 === t0 ? 0 : (ms - t0) / (t1 - t0)) * (W - L - R);
  const floor = 55;
  const Y = v => T + ((v === null ? floor : v) - 1) / (floor - 1) * (H - T - B);
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const fmt = d => { const x = new Date(d + 'T00:00:00'); return x.getDate() + ' ' + months[x.getMonth()]; };
  let g = '';
  [1, 10, 20, 30, 40, 50].forEach(v => {
    g += '<line class="grid" x1="' + L + '" x2="' + (W - R) + '" y1="' + Y(v) + '" y2="' + Y(v) + '"/>' +
         '<text class="axis" x="' + (L - 6) + '" y="' + (Y(v) + 4) + '" text-anchor="end">' + v + '</text>';
  });
  g += '<text class="axis" x="' + (L - 6) + '" y="' + (Y(null) + 4) + '" text-anchor="end">50+</text>';
  // Date labels: first, last, and as many between as fit.
  // Date labels: the last always, then working back, any that leave 44px clear.
  const shown = [];
  for (let i = hist.dates.length - 1; i >= 0; i--) {
    const x = X(t[i]);
    if (shown.every(o => Math.abs(o - x) >= 44)) {
      shown.push(x);
      g += '<text class="axis" x="' + x + '" y="' + (H - 6) + '" text-anchor="middle">' + fmt(hist.dates[i]) + '</text>';
    }
  }
  for (let i = 1; i < hist.dates.length; i++) {
    if (hist.weights[i] !== hist.weights[i - 1]) {
      const xm = (X(t[i - 1]) + X(t[i])) / 2;
      g += '<line class="wchange" x1="' + xm + '" x2="' + xm + '" y1="' + T + '" y2="' + (H - B) + '"/>' +
           '<text class="axis halo" x="' + (xm - 4) + '" y="' + (H - B - 6) + '" text-anchor="end">weights changed</text>';
    }
  }
  // Labels at the right edge, nudged apart so none overlap.
  const lastY = top.map(n => ({n, y: Y(hist.ranks[n][hist.dates.length - 1])})).sort((a, b) => a.y - b.y);
  for (let i = 1; i < lastY.length; i++) lastY[i].y = Math.max(lastY[i].y, lastY[i - 1].y + 12);
  const labelY = Object.fromEntries(lastY.map(o => [o.n, o.y]));
  let series = '';
  top.forEach((n, k) => {
    const r = hist.ranks[n];
    let d = '', pts = '';
    r.forEach((v, i) => {
      const yy = Y(v);
      d += (i ? 'L' : 'M') + X(t[i]).toFixed(1) + ' ' + yy.toFixed(1);
      pts += '<circle class="pt" r="4" cx="' + X(t[i]) + '" cy="' + yy + '" data-i="' + i + '"/>';
    });
    const ly = labelY[n], ry = Y(r[r.length - 1]);
    series += '<g class="s" data-n="' + esc(n) + '">' +
      '<path class="ln" d="' + d + '"/><path class="hit" d="' + d + '"/>' + pts +
      (Math.abs(ly - ry) > 1 ? '<path class="ln" d="M' + (W - R + 2) + ' ' + ry + 'L' + (W - R + 10) + ' ' + ly + '" stroke-width="1"/>' : '') +
      '<text class="lbl" x="' + (W - R + 14) + '" y="' + (ly + 4) + '">' + (k + 1) + '. ' +
        esc(narrow && n.length > 15 ? n.slice(0, 14) + '…' : n) + '</text></g>';
  });
  const VH = Math.max(H, lastY[lastY.length - 1].y + 16);
  box.innerHTML = '<svg width="' + W + '" height="' + VH + '" viewBox="0 0 ' + W + ' ' + VH + '" role="img" aria-label="Weekly position of the top 15 artists">' +
    g + series + '</svg><div class="tip" hidden></div>';
  const svg = box.querySelector('svg'), tip = box.querySelector('.tip');
  const focus = n => svg.querySelectorAll('g.s').forEach(el => el.classList.toggle('on', el.dataset.n === n));
  svg.addEventListener('click', e => {
    const s = e.target.closest('g.s');
    picked = s && picked !== s.dataset.n ? s.dataset.n : null;
    focus(picked);
  });
  svg.addEventListener('mouseover', e => {
    const s = e.target.closest('g.s');
    if (!picked) focus(s ? s.dataset.n : null);
    const c = e.target.closest('circle.pt');
    if (c && s) {
      const i = +c.dataset.i, v = hist.ranks[s.dataset.n][i];
      const b = box.getBoundingClientRect(), cb = c.getBoundingClientRect();
      tip.textContent = s.dataset.n + ' · ' + fmt(hist.dates[i]) + ': ' + (v === null ? 'outside the top 50' : '#' + v);
      tip.style.left = (cb.left + cb.width / 2 - b.left) + 'px';
      tip.style.top = (cb.top - b.top) + 'px';
      tip.hidden = false;
    }
  });
  svg.addEventListener('mouseout', e => {
    if (e.target.closest('circle.pt')) tip.hidden = true;
    if (!picked && !e.relatedTarget?.closest?.('g.s')) focus(null);
  });
  focus(picked || top[0]);
  };
  draw();
  let lastW = box.clientWidth;
  window.addEventListener('resize', () => { if (box.clientWidth !== lastW) { lastW = box.clientWidth; draw(); } });
})();
// Following is not scored (it docks whoever I have not got round to yet), so
// the gap becomes a to-do instead: favourites on the page I do not follow.
const unfollowed = favs.filter(a => a.fol !== 'y');
if (unfollowed.length) {
  const el = document.getElementById('unfollowed');
  el.hidden = false;
  el.innerHTML = '<b>Not followed yet (' + unfollowed.length + '):</b> ' +
    unfollowed.map(a => artistLink(a.name) + ' <span class="rank">#' + a.rank + '</span>').join(', ') +
    '. Follow them in Spotify and they drop off this list.';
}
document.getElementById('disc').innerHTML = disc.map(a =>
  '<div class="row' + clubCls(a.name) + '"><div class="rank">' + a.rank + '</div>' +
  '<div><div class="name">' + artistLink(a.name, a.id) + '</div>' +
  '<div class="meta">via ' + linkList(a.from.split(', ')) + '</div></div>' +
  '<div class="score">' + a.votes + '</div></div>'
).join('');
// The pool is every eligible album, ranked. "Show me twenty others" puts the
// ones on screen aside and recalculates from what is left, applying the same
// one-per-artist rule as album_recs.sh. The set-aside list lives in this
// browser only and clears when the weekly data changes.
const skipKey = 'albumsSkipped';
const loadSkips = () => {
  try {
    const s = JSON.parse(localStorage.getItem(skipKey) || 'null');
    return s && s.stamp === albumStamp ? s.keys : [];
  } catch (e) { return []; }
};
const saveSkips = keys => {
  try { localStorage.setItem(skipKey, JSON.stringify({stamp: albumStamp, keys})); } catch (e) {}
};
let skipped = loadSkips();
let shown = [];
const pickAlbums = () => {
  const skip = new Set(skipped), per = {}, out = [];
  for (const a of albumPool) {
    if (skip.has(a.k) || (per[a.a] || 0) >= albumPer) continue;
    per[a.a] = (per[a.a] || 0) + 1;
    out.push(a);
    if (out.length === albumCount) break;
  }
  return out;
};
const renderAlbums = () => {
  shown = pickAlbums();
  document.getElementById('albums').innerHTML = shown.map((a, i) => {
    const why = [a.source === 'known' ? 'favourite' : 'new to me, via ' + esc(a.from)];
    if (a.hits > 0) why.push(a.hits + ' of their top tracks');
    const chip = a.new ? '<span class="chip">new</span>' : '';
    return '<div class="row' + clubCls(a.artist) + '"><div class="rank">' + (i + 1) + '</div>' +
      '<div><div class="name"><a href="spotify:album:' + a.id + '">' + esc(a.album) + '</a>' + chip + '</div>' +
      '<div class="meta">' + artistLink(a.artist, a.a) + ' &middot; ' + a.year + ' &middot; ' + why.join(' &middot; ') + '</div></div>' +
      '<div class="score">' + a.score + '</div></div>';
  }).join('') || '<div class="row"><div></div><div class="meta">Nothing left in the pool. Go back to this week\'s list.</div><div></div></div>';
  const sets = Math.round(skipped.length / albumCount);
  document.getElementById('albumsReset').hidden = skipped.length === 0;
  document.getElementById('albumsNext').disabled = shown.length === 0;
  document.getElementById('albumsState').textContent = skipped.length ? sets + (sets === 1 ? ' set' : ' sets') + ' put aside' : '';
};
document.getElementById('albumsNext').addEventListener('click', () => {
  skipped = skipped.concat(shown.map(a => a.k));
  saveSkips(skipped); renderAlbums();

  document.getElementById('albums').scrollIntoView({block: 'start'});
});
document.getElementById('albumsReset').addEventListener('click', () => {
  skipped = []; saveSkips(skipped); renderAlbums();
});
renderAlbums();

const gigData = $gigs;
if (gigData) {
  document.getElementById('gigsection').hidden = false;
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const when = g => {
    const d = new Date(g.date + 'T12:00:00');
    const [h, m] = g.time.split(':').map(Number);
    const t = (h % 12 || 12) + (m ? ':' + String(m).padStart(2, '0') : '') + (h < 12 ? 'am' : 'pm');
    return '<b>' + days[d.getDay()] + ' ' + d.getDate() + '</b>' + months[d.getMonth()] + '<br>' + t;
  };
  const actHtml = a => {
    const cls = a.kind === 'known' ? 'act-fav' : (a.score >= 5 ? '' : 'act-dim');
    return '<span class="' + cls + '">' + artistLink(a.name, a.id) + '</span>';
  };
  const whyHtml = g => g.acts.filter(a => a.score >= 1 && (a.rank || (a.via && a.via.length))).slice(0, 3).map(a =>
    a.rank ? esc(a.name) + ' is favourite #' + a.rank
           : esc(a.name) + ' sounds like ' + linkList(a.via) + (a.guess ? ' <span class="chip guess">guess</span>' : '')
  ).join(' &middot; ');
  const row = g => '<div class="row gigrow' + clubCls(g.acts.map(a => a.name)) + '">' +
    '<a class="gigdate" href="gigs/' + g.key + '.ics">' + when(g) + '</a>' +
    '<div><div class="name">' + g.acts.map(actHtml).join(' &middot; ') +
      (g.new ? '<span class="chip">new</span>' : '') + (g.free ? '<span class="chip">free</span>' : '') + '</div>' +
    '<div class="meta">' + (g.link ? '<a href="' + esc(g.link) + '">' + esc(g.venue) + '</a>' : esc(g.venue)) +
      (g.suburb ? ', ' + esc(g.suburb) : '') + (whyHtml(g) ? ' &middot; ' + whyHtml(g) : '') + '</div></div>' +
    '<div class="score">' + g.score + '</div></div>';
  const block = (title, list, empty) => '<h3>' + title + '</h3>' +
    (list.length ? '<div class="list">' + list.map(row).join('') + '</div>' : '<p class="note">' + empty + '</p>');
  const nd = gigData.nodata;
  document.getElementById('gigs').className = 'gigs';
  document.getElementById('gigs').innerHTML =
    block('New announcements', gigData.new, 'Nothing new from your top 100 since last week.') +
    block('Coming up', gigData.coming, 'Nothing above the cut-off in the next eight weeks.') +
    block('Further out', gigData.later, 'Nothing above the cut-off further ahead yet.') +
    '<details class="nodata"><summary>' + nd.length + ' gigs Spotify cannot place yet' +
      (gigData.pending_acts ? ' (' + gigData.pending_acts + ' acts not looked up yet)' : '') + '</summary>' +
    '<div class="list">' + nd.map(g => '<div class="row' + clubCls(g.acts) + '"><div class="gigdate">' + when(g) + '</div><div>' +
      g.acts.map(n => artistLink(n)).join(' · ') + ' <span class="meta">' +
      (g.link ? '<a href="' + esc(g.link) + '">' + esc(g.venue) + '</a>' : esc(g.venue)) + '</span></div></div>').join('') +
    '</div></details>';
}
// One column per signal that carries weight, heaviest first, so the table
// follows weights.json without editing: a signal set to zero drops out.
const flag = v => v ? 'yes' : 'no';
const signals = [
  ['yearly', 'Yearly wraps', a => a.yearly ? a.yearly.toFixed(2) + ' · ' + a.years + (a.years === 1 ? ' yr' : ' yrs') : '0'],
  ['top', 'Top tracks', a => a.top + ' of 50'],
  ['spread', 'Spread', a => a.spread + ' pl'],
  ['favourite', 'Favourite', a => flag(a.favourite)],
  ['tracks', 'Tracks', a => a.tracks + ' trk'],
  ['followed', 'Followed', a => flag(a.followed)],
  ['dedicated', 'Best of', a => flag(a.dedicated)],
  ['activity', 'Releases', a => a.activity.toFixed(2)],
  ['alltime', 'All-time', a => '']
].filter(s => (weights[s[0]] || 0) > 0)
 .sort((x, y) => weights[y[0]] - weights[x[0]]);
const fmt = n => (Math.round(n * 10) / 10).toFixed(1);
// Every heading sorts its column. A first click puts the strongest first
// (most points, or A to Z for names, or rank 1 for rank); a second reverses.
// Ties fall back to rank, so equal scores keep the ranking order.
const columns = [
  {key: 'rank', label: '#', cls: 'pin r', value: a => a.rank, asc: true},
  {key: 'name', label: 'Artist', cls: 'pin n', value: a => a.name.toLowerCase(), asc: true},
  {key: 'score', label: 'Score', max: '/100', value: a => a.score}
].concat(signals.map(s => ({key: s[0], label: s[1],
  max: '/' + String(Math.round(weights[s[0]] * 1000) / 10), value: a => a.points[s[0]] || 0})))
 .concat([{key: 'story', label: 'Story', cls: 'storyh', value: a => (stories[a.name] || {}).archetype || '~', asc: true}]);
let sort = {key: 'rank', asc: true};
const header = () => '<thead><tr>' + columns.map(c => {
  const on = sort.key === c.key;
  const arrow = on ? (sort.asc === !!c.asc ? '▾' : '▴') : '';
  return '<th' + (c.cls ? ' class="' + c.cls + '"' : '') +
    (on ? ' aria-sort="' + (sort.asc ? 'ascending' : 'descending') + '"' : '') +
    '><button type="button" data-key="' + c.key + '">' +
    (c.cls ? '' : '<span class="arrow">' + arrow + '</span>') + c.label +
    (c.cls ? '<span class="arrow">' + arrow + '</span>' : '') +
    (c.max ? '<span class="w">' + c.max + '</span>' : '') + '</button></th>';
}).join('') + '</tr></thead>';
const sorted = () => {
  const col = columns.find(c => c.key === sort.key);
  const dir = sort.asc ? 1 : -1;
  return brk.slice().sort((x, y) => {
    const a = col.value(x), b = col.value(y);
    if (a < b) return -dir;
    if (a > b) return dir;
    return x.rank - y.rank;
  });
};
const rows = list => '<tbody>' + list.map(a =>
  '<tr' + (isClub(a.name) ? ' class="club"' : '') + '><td class="pin r">' + a.rank + '</td><td class="pin n" title="' + esc(a.name) + '">' + artistLink(a.name) + '</td>' +
  '<td class="total">' + fmt(a.score) + '</td>' +
  signals.map(s => {
    const p = a.points[s[0]] || 0;
    // Shade by how much of the signal the artist earned, so the shape of a
    // ranking reads before any number does.
    const share = Math.min(1, p / (weights[s[0]] * 100));
    const bg = p > 0 ? ' style="background: color-mix(in srgb, var(--accent) ' + Math.round(share * 22) + '%, transparent)"' : '';
    return '<td' + (p > 0 ? '' : ' class="zero"') + bg + '><b>' + fmt(p) + '</b><span class="raw">' + esc(s[2](a)) + '</span></td>';
  }).join('') +
  '<td class="story">' + (stories[a.name] ? '<span class="arch">' + esc(stories[a.name].label || stories[a.name].archetype) + '</span>' +
    esc(stories[a.name].story) : '') + '</td></tr>').join('') + '</tbody>';
const table = document.getElementById('brk');
const render = () => { table.innerHTML = header() + rows(sorted()); };
// Tapping a heading also explains it: what the signal measures, its weight in
// weights.json, and so the most points it can add to the 100.
const about = {
  rank: ['Rank', 'Position in the favourites ranking, by total score.'],
  name: ['Artist', 'Tap to sort A to Z.'],
  score: ['Score', 'The total out of 100: the sum of the points in every signal column. Each column\'s ceiling is its weight × 100.'],
  yearly: ['Yearly wraps', 'Tracks in every "Your Top Songs" playlist Spotify has made you, recent years counting more (half-life ' + (tuning.yearly_half_life_years || 3) + ' years). Ten years of what you actually played.'],
  top: ['Top tracks', 'How many of your 50 current top tracks are theirs. Spotify\'s short-term window: the only signal that reflects now.'],
  spread: ['Spread', 'How many different playlists of yours hold two or more of their tracks.'],
  tracks: ['Tracks', 'Their tracks across your playlists, counting at most ' + (tuning.track_cap || 5) + ' per playlist, so one long Best Of cannot outvote years of listening.'],
  favourite: ['Favourite', 'Whether they are in the favourites playlist you keep by hand. Yes or no.'],
  followed: ['Followed', 'Whether you follow them on Spotify. Yes or no, and cheap: you follow once and forget.'],
  dedicated: ['Best of', 'Whether more than half of some playlist of five or more tracks is theirs. Yes or no.'],
  activity: ['Releases', 'New albums and singles in the last three years, reissues excluded. Nearly switched off.'],
  story: ['Story', 'Why they sit where they do, worked out from your data alone by bin/artist_stories.py: the same data always gives the same story. Tap to group by kind of story.'],
  alltime: ['All-time', 'Spotify\'s All-Time Top Songs playlist. Switched off: Spotify does not keep it current.']
};
const toast = document.getElementById('toast');
let toastTimer;
const explain = key => {
  const [title, text] = about[key] || [key, ''];
  const w = weights[key];
  const weightLine = w ? 'Weight ' + (Math.round(w * 100) / 100) + ' in weights.json, so up to ' +
    (Math.round(w * 1000) / 10) + ' of the 100 points.' : '';
  toast.innerHTML = '<b>' + esc(title) + '</b>' + esc(text) + (weightLine ? ' ' + esc(weightLine) : '');
  toast.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('on'), 6000);
};
toast.addEventListener('click', () => toast.classList.remove('on'));
table.addEventListener('click', e => {
  const btn = e.target.closest('button[data-key]');
  if (!btn) return;
  explain(btn.dataset.key);
  const col = columns.find(c => c.key === btn.dataset.key);
  sort = sort.key === col.key ? {key: col.key, asc: !sort.asc} : {key: col.key, asc: !!col.asc};
  render();
});
render();
</script>
</body>
</html>
HTML

echo "page -> $out ($(wc -c < "$out" | tr -d ' ') bytes)"
