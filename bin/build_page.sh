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

disc=$(jq -c --argjson n "$disc_n" '[.[0:$n][] |
  {rank, score, votes, name, from: (.from | join(", "))}]' "$root/discover_artists.json")

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
.rank { color: var(--muted); font-variant-numeric: tabular-nums; font-size: 14px; }
.name { font-weight: 550; }
.meta { color: var(--muted); font-size: 13px; margin-top: 3px; }
.score {
  font-variant-numeric: tabular-nums; color: var(--accent);
  font-size: 14px; font-weight: 600;
}
.chip {
  display: inline-block; background: var(--chip); color: var(--muted);
  border-radius: 10px; padding: 1px 7px; font-size: 11px; margin-left: 6px;
  vertical-align: 1px; letter-spacing: 0.02em;
}
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
</header>

<h2>Favourite artists</h2>
<p class="note">Scored across playlist breadth and depth, current top tracks, a
hand-kept favourites playlist, dedicated playlists, follows and recent releases.
Updated weekly.</p>
<div class="list" id="favs"></div>

<h2>Worth investigating</h2>
<p class="note">Artists absent from my library, ranked by which of my favourites
Spotify says they resemble &mdash; a nod from a higher-ranked artist counts for
more. Household names I simply have not saved can still slip through.</p>
<div class="list" id="disc"></div>

<footer>Built from Spotify data by <code>bin/build_page.sh</code>.</footer>
</div>
<script>
const favs = $favs;
const disc = $disc;
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
  return '<div class="row"><div class="rank">' + a.rank + '</div>' +
    '<div><div class="name">' + esc(a.name) + chips + '</div>' +
    '<div class="meta">' + bits.join(' &middot; ') + '</div></div>' +
    '<div class="score">' + a.score + '</div></div>';
}).join('');
document.getElementById('disc').innerHTML = disc.map(a =>
  '<div class="row"><div class="rank">' + a.rank + '</div>' +
  '<div><div class="name">' + esc(a.name) + '</div>' +
  '<div class="meta">via ' + esc(a.from) + '</div></div>' +
  '<div class="score">' + a.votes + '</div></div>'
).join('');
</script>
</body>
</html>
HTML

echo "page -> $out ($(wc -c < "$out" | tr -d ' ') bytes)"
