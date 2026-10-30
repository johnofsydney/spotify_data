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
weights=$(jq -c '.config.weights | ([.[]] | add) as $s | map_values(if $s > 1.5 then . / 100 else . end)' "$root/favourite_artists.json")

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
/* The breakdown is a reference table, not a list to read down: denser type,
   a grid, and a sideways scroll on a phone with rank and name pinned. */
.tablewrap { overflow-x: auto; -webkit-overflow-scrolling: touch; border-top: 1px solid var(--line); }
table.brk { border-collapse: collapse; font-size: 12px; line-height: 1.25; width: 100%; font-variant-numeric: tabular-nums; }
.brk th, .brk td { padding: 6px 7px; border-bottom: 1px solid var(--line); text-align: right; white-space: nowrap; vertical-align: top; }
.brk thead th { font-weight: 600; color: var(--muted); font-size: 11px; letter-spacing: 0.02em; vertical-align: bottom; }
.brk thead th .w { display: block; font-weight: 400; color: var(--accent); }
.brk .pin { position: sticky; background: var(--bg); z-index: 1; text-align: left; }
.brk .pin.r { left: 0; min-width: 26px; color: var(--muted); }
.brk .pin.n { left: 26px; max-width: 150px; overflow: hidden; text-overflow: ellipsis; font-weight: 550; border-right: 1px solid var(--line); }
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
</header>

<h2>Favourite artists</h2>
<p class="note">Scored across ten years of Spotify's yearly top songs, current top
tracks, playlist breadth and depth, a hand-kept favourites playlist, dedicated
playlists, follows and recent releases. Updated weekly.</p>
<div class="list" id="favs"></div>

<h2>Worth investigating</h2>
<p class="note">Artists absent from my library, ranked by which of my favourites
Spotify says they resemble &mdash; a nod from a higher-ranked artist counts for
more. Household names I simply have not saved can still slip through.</p>
<div class="list" id="disc"></div>

<h2>Score breakdown</h2>
<p class="note">How each of the top fifty earns its score. In each cell the bold
figure is the points that signal contributes, out of the most it can give (under
the heading), and the small figure is the raw measurement. The points add up to
the score. Counts are square-rooted against the highest of any artist, so the
first few tracks earn far more than the fortieth.</p>
<div class="tablewrap"><table class="brk" id="brk"></table></div>

<footer>Built from Spotify data by <code>bin/build_page.sh</code>.</footer>
</div>
<script>
const favs = $favs;
const disc = $disc;
const brk = $brk;
const weights = $weights;
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
const head = '<thead><tr><th class="pin r">#</th><th class="pin n">Artist</th><th>Score<span class="w">/100</span></th>' +
  signals.map(s => '<th>' + s[1] + '<span class="w">/' + String(Math.round(weights[s[0]] * 1000) / 10) + '</span></th>').join('') +
  '</tr></thead>';
const body = '<tbody>' + brk.map(a =>
  '<tr><td class="pin r">' + a.rank + '</td><td class="pin n" title="' + esc(a.name) + '">' + esc(a.name) + '</td>' +
  '<td class="total">' + fmt(a.score) + '</td>' +
  signals.map(s => {
    const p = a.points[s[0]] || 0;
    // Shade by how much of the signal the artist earned, so the shape of a
    // ranking reads before any number does.
    const share = Math.min(1, p / (weights[s[0]] * 100));
    const bg = p > 0 ? ' style="background: color-mix(in srgb, var(--accent) ' + Math.round(share * 22) + '%, transparent)"' : '';
    return '<td' + (p > 0 ? '' : ' class="zero"') + bg + '><b>' + fmt(p) + '</b><span class="raw">' + esc(s[2](a)) + '</span></td>';
  }).join('') + '</tr>').join('') + '</tbody>';
document.getElementById('brk').innerHTML = head + body;
</script>
</body>
</html>
HTML

echo "page -> $out ($(wc -c < "$out" | tr -d ' ') bytes)"
