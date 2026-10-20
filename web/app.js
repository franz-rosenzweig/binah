// Binah's web client: routing, Today, Practice, Skills, the golden set, Settings, sign-in.
// The games are in play.js and the monthly benchmark in bench.js. Native shells talk to the page
// through shell.js. One page, two looks (style.css): Apple-like on desktop and in the Mac app,
// Material 3 on phones and in the Android app, where <html> gets `m3`.
import { play, goldenPlay } from './play.js';
import { bench } from './bench.js';
import './shell.js';

export const $ = (s, el = document) => el.querySelector(s);
export const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const words = t => (String(t || '').trim().match(/\S+/g) || []).length;
const main = $('#main');

// ── the look ──
const narrow = matchMedia('(max-width: 899px)');
function setLook() { const h = document.documentElement; h.classList.toggle('m3', narrow.matches || h.classList.contains('shell-android')); }
setLook();
narrow.addEventListener('change', () => { setLook(); if (state.me && state.me.signed_in) render(); });
export const isM3 = () => document.documentElement.classList.contains('m3');

export async function api(path, opts = {}) {
  const init = { method: opts.method || (opts.body !== undefined ? 'POST' : 'GET'), credentials: 'same-origin', headers: {} };
  if (opts.body instanceof FormData) init.body = opts.body;
  else if (opts.body !== undefined) { init.body = JSON.stringify(opts.body); init.headers['Content-Type'] = 'application/json'; }
  const r = await fetch(path, init);
  if (r.status === 401 && path !== '/api/login') { signin(); throw new Error('signed out'); }
  let data = null;
  try { data = await r.json(); } catch { data = null; }
  if (!r.ok) throw new Error((data && data.detail) || `Something went wrong (${r.status})`);
  return data;
}

export function toast(m) { const t = $('#toast'); t.textContent = m; t.classList.add('show'); clearTimeout(toast.h); toast.h = setTimeout(() => t.classList.remove('show'), 2600); }
export const haptic = kind => window.binahShell?.haptic?.(kind);

// ── icons (24px grid, stroked in currentColor) ──
const P = {
  today: '<rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>',
  practice: '<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
  skills: '<path d="M5 20v-8M12 20V5M19 20v-11"/>',
  golden: '<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/>',
  bench: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  settings: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  back: '<path d="M15 6l-6 6 6 6"/>',
  arrow: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  chev: '<path d="M9 6l6 6-6 6"/>',
  check: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16 9.5"/>',
  tick: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  u: '<path d="M4 5.5c2.5-1 5.5-1 8 .5 2.5-1.5 5.5-1.5 8-.5V19c-2.5-1-5.5-1-8 .5-2.5-1.5-5.5-1.5-8-.5zM12 6v13.5"/>',
  r: '<path d="M12 4v16M5 8h14M7 8l-3 6h6zM17 8l-3 6h6z"/>',
  e: '<path d="M4 20l1-4L16 5l3 3L8 19zM14 7l3 3"/>',
  s: '<path d="M4 12h1M7.5 8v8M11 5v14M14.5 9v6M18 7v10M21 12h-1"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
  stop: '<rect x="7" y="7" width="10" height="10" rx="2.5" fill="currentColor" stroke="none"/>',
};
export const icon = (k, cls = '') => `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[k] || ''}</svg>`;
export const PLAY = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l12.5-7.5z"/></svg>';
export const PILLAR_OF = { gist: 'u', subtext: 'u', weak: 'r', tech: 'r', word: 'e', bloat: 'e', jam: 's' };
export const PILLAR = { u: 'Understand', r: 'Reason', e: 'Express', s: 'Speak' };
export const sq = p => `<span class="sq ${p}">${icon(p)}</span>`;

// The header of every screen: a toolbar row on desktop; a large title (tabs) or a top app bar (games) on Material.
export function bar({ title, sub = '', back = null, actions = '', kind = 'big' }) {
  return `<header class="bar ${kind}">${back ? `<button class="back" type="button" id="barBack" aria-label="Back">${icon('back', 'd-only')}${icon('arrow', 'm-only')}</button>` : ''}
    <div class="bar-t"><h1>${esc(title)}</h1>${sub ? `<span>${esc(sub)}</span>` : ''}</div>${actions ? `<div class="bar-a">${actions}</div>` : ''}</header>`;
}

// ── the frame: sidebar (desktop) and bottom bar (Material) ──
const TRAIN = [['today', 'Today'], ['practice', 'Practice'], ['skills', 'Skills']];
const MEASURE = [['golden', 'Golden Set'], ['bench', 'Benchmark'], ['settings', 'Settings']];
const TABS = [['today', 'Today'], ['practice', 'Practice'], ['skills', 'Skills'], ['golden', 'Golden set']];

function navCount(k) {
  const n = state.nav;
  if (!n) return '';
  if (k === 'today' && n.today.total) return `<span class="ct">${n.today.done} of ${n.today.total}</span>`;
  if (k === 'golden') return `<span class="ct">${n.golden.n} of ${n.golden.target}</span>`;
  if (k === 'bench' && n.bench_due) return '<span class="due">Due</span>';
  return '';
}
function weekRing(w) {
  const frac = w.goal ? Math.min(1, w.active / w.goal) : 0, C = 2 * Math.PI * 14;
  return `<svg viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="14" fill="none" stroke="var(--sunk)" stroke-width="4"/><circle cx="18" cy="18" r="14" fill="none" stroke="var(--accent)" stroke-width="4" stroke-linecap="round" stroke-dasharray="${(C * frac).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 18 18)"/></svg>`;
}
const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

function chrome(on, current) {
  $('#rail').hidden = !on; $('#tabbar').hidden = !on;
  if (!on) return;
  const sec = (name, items) => `<div class="navsec"><h2>${name}</h2>${items.map(([k, n]) => `<button type="button" data-go="${k}" ${current === k ? 'aria-current="page"' : ''}>${icon(k)}<span class="nm">${n}</span>${navCount(k)}</button>`).join('')}</div>`;
  const n = state.nav;
  $('#nav').innerHTML = sec('Train', TRAIN) + sec('Measure', MEASURE)
    + (n ? `<div class="wk">${weekRing(n.week)}<div><b>${n.week.active} of ${n.week.goal} days this week</b><span>${n.rest_weekday != null ? `${DAYS[n.rest_weekday]} is your rest day` : 'No rest day set'}</span></div></div>` : '');
  $('#tabbar').innerHTML = TABS.map(([k, name]) => `<button type="button" data-go="${k}" ${current === k ? 'aria-current="page"' : ''}><span class="pill">${icon(k)}</span>${name}</button>`).join('');
  document.querySelectorAll('[data-go]').forEach(b => b.onclick = () => { haptic('tick'); go(b.dataset.go); });
}
async function refreshNav(current) {
  try { state.nav = await api('/api/nav'); } catch { return; }
  if (state.route !== current) return;
  const hid = $('#tabbar').hidden;
  chrome(true, current === 'play' ? 'practice' : current === 'gold' ? 'golden' : current);
  $('#tabbar').hidden = hid;
}

export const state = { route: 'today', me: null, today: null, back: null, nav: null };
export function go(route) { if (location.hash.slice(1) === route) render(); else location.hash = route; }
window.addEventListener('hashchange', render);

async function boot() {
  try { state.me = await api('/api/me'); } catch { state.me = null; }
  if (!state.me || !state.me.signed_in) return signin();
  render();
}

function signin() {
  chrome(false);
  state.route = 'signin';
  main.innerHTML = `<form class="signin" id="signin" autocomplete="on">
    <div class="mark"><b>binah</b><span class="he" lang="he">בינה</span></div>
    <p class="muted">Understanding, trained on real text.</p>
    <label class="form"><span class="small">Username</span><input class="inp" id="u" name="username" autocomplete="username" autocapitalize="off" required></label>
    <label class="form"><span class="small">Password</span><input class="inp" id="p" name="password" type="password" autocomplete="current-password" required></label>
    <button class="btn" type="submit">Sign in</button><p class="err" id="err" hidden></p></form>`;
  $('#signin').onsubmit = async e => {
    e.preventDefault();
    try { await api('/api/login', { body: { user: $('#u').value, password: $('#p').value } }); state.me = await api('/api/me'); go('today'); render(); }
    catch (err) { const el = $('#err'); el.hidden = false; el.textContent = err.message; }
  };
}

async function render() {
  if (!state.me || !state.me.signed_in) return;
  const [route, ...rest] = (location.hash.slice(1) || 'today').split('/');
  state.route = route;
  state.back = null;
  window.scrollTo(0, 0);
  const tab = route === 'play' ? 'practice' : route === 'gold' ? 'golden' : route;
  chrome(true, tab);
  if (route === 'play' || route === 'gold' || (route === 'bench' && rest[0] === 'run')) $('#tabbar').hidden = true;   // a game has the screen to itself on a phone
  refreshNav(route);
  if (route === 'play') return play(rest[0], rest[1] ? rest[1].split(',') : null, { day: rest[2] || null, slot: rest[3] ?? null });
  if (route === 'gold') return goldenPlay(rest[0]);
  if (route === 'bench') return bench(rest);
  try {
    if (route === 'practice') return await practice();
    if (route === 'skills') return await skills();
    if (route === 'golden') return await golden();
    if (route === 'settings') return await settings();
    return await today();
  } catch (e) { if (e.message !== 'signed out') main.innerHTML = bar({ title: 'Binah' }) + `<div class="body"><p class="err">${esc(e.message)}</p></div>`; }
}

// ── Today ──

const avg = a => a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0;
const pct = x => `${Math.round(100 * x)}%`;

function ring72(done, total) {
  const C = 2 * Math.PI * 30, f = total ? done / total : 0;
  return `<div class="ring72 d-only"><svg viewBox="0 0 72 72" aria-hidden="true"><circle cx="36" cy="36" r="30" fill="none" stroke="var(--sunk)" stroke-width="7"/><circle cx="36" cy="36" r="30" fill="none" stroke="var(--accent)" stroke-width="7" stroke-linecap="round" stroke-dasharray="${(C * f).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 36 36)"/></svg><span>${done}/${total}</span></div>`;
}
function wave(done, total) {
  // Material's wavy progress line: the done part waves, the rest is a flat track
  const W = 318, x = 6 + (W - 12) * (total ? done / total : 0);
  let d = 'M6 6';
  for (let p = 6; p + 12 <= x; p += 12) d += ' q 3 -5 6 0 t 6 0';
  return `<svg class="wave m-only" viewBox="0 0 ${W} 12" preserveAspectRatio="none" role="img" aria-label="${done} of ${total} done"><path d="M${Math.max(6, x + 6)} 6 H ${W - 6}" fill="none" stroke="currentColor" stroke-opacity=".22" stroke-width="5" stroke-linecap="round"/>${x > 12 ? `<path d="${d}" fill="none" stroke="var(--accent)" stroke-width="5" stroke-linecap="round"/>` : ''}</svg>`;
}

async function today() {
  const t = state.today = await api('/api/today');
  const ed = t.edition;
  const d = new Date(ed.day + 'T12:00:00');
  const dateLine = d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
  const done = ed.slots.filter(s => s.done).length, total = ed.slots.length;
  const mins = ed.slots.reduce((a, s) => a + (s.done ? 0 : s.minutes), 0);
  const nextSlot = ed.slots.find(s => !s.done);
  const nextName = nextSlot ? t.games[nextSlot.game].name : null;
  const open = s => { haptic('tick'); location.hash = `play/${s.game}/${s.items.join(',')}/${ed.day}/${s.slot}`; };

  const rows = ed.slots.map(s => {
    const g = t.games[s.game], p = s.pillar || PILLAR_OF[s.game];
    const score = s.scores && s.scores.filter(x => x != null);
    const right = s.done ? `<span class="ok">${icon('check', 'd-only')}${icon('tick', 'm-only')}${score && score.length ? pct(avg(score)) : 'done'}</span>`
      : `${s === nextSlot ? '<span class="badge">Next</span>' : ''}${s.answered ? `<span class="wait">${s.answered}/${s.items.length}</span>` : `<span class="d-only">${g.minutes} min</span>`}${icon('chev', 'chev')}`;
    return `<button class="li ${s === nextSlot ? 'next' : ''}" type="button" data-slot="${s.slot}">${sq(p)}<span class="li-t"><b>${esc(g.name)}</b><small>${esc(PILLAR[p])}${s.source ? ' · ' + esc(s.source) : isM3() ? ` · ${g.minutes} min` : ''}</small></span><span class="li-r">${right}</span></button>`;
  }).join('');

  const hero = ed.finished || !nextSlot
    ? `<section class="hero">${ring72(done, total)}<div class="hero-t"><span class="kick m-only">Today's edition</span><h2>Today's edition is done.</h2><p>Tomorrow opens with a recall card on today's passage. Anything else today is extra, in Practice.</p></div><div class="hero-b"><button class="btn ghost" type="button" id="toPractice">Practice</button></div></section>`
    : `<section class="hero">${ring72(done, total)}<div class="hero-t"><span class="kick m-only">Today's edition</span>
        <h2><span class="d-only">Today's edition</span><span class="m-only">Next: ${esc(nextName)}</span></h2>
        <p>${isM3() ? `${done} of ${total} games` : `${total} games`} · about ${Math.max(1, mins)} minutes left</p>
        <p class="next d-only">Next is ${esc(nextName)}${nextSlot.source ? `, from ${esc(nextSlot.source)}` : ''}.</p></div>
        ${wave(done, total)}<div class="hero-b"><button class="btn" type="button" id="cont">${isM3() ? PLAY : ''}Continue</button><button class="btn ghost m-only" type="button" id="toPractice">Practice</button></div></section>`;

  const recall = ed.recall && !ed.recall.mark ? `<section class="card" id="recall"><span class="label">Before you start</span><p style="margin-top:6px">Yesterday you read a passage${ed.recall.book ? ` from <b>${esc(ed.recall.book)}</b>` : ''}. What was its point?</p>
      <textarea class="ta" id="rcT" style="min-height:64px;margin-top:8px" aria-label="What you remember"></textarea><button class="btn ghost" id="rcShow" type="button">Check against yesterday's reference</button><div id="rcOut"></div></section>` : '';

  const w = t.week;
  const days = w.days.map(x => { const L = new Date(x.day + 'T12:00:00').toLocaleDateString(undefined, { weekday: 'narrow' }); return `<span class="day ${x.answers ? 'on' : ''} ${x.rest ? 'rest' : ''} ${x.today ? 'today' : ''} ${x.future ? 'future' : ''}" title="${esc(x.day)}"><em>${L}</em><i>${L}</i></span>`; }).join('');
  const c = t.counts;
  main.innerHTML = bar({ title: 'Today', sub: dateLine, actions: `${!ed.finished && nextSlot ? `<button class="btn d-only" type="button" id="contTop" style="margin:0">${PLAY}Continue Edition</button>` : ''}<button class="ibtn m-only" type="button" data-go2="settings" aria-label="Settings">${icon('settings')}</button>` })
    + `<div class="body">${hero}${recall}
      <section class="sec"><h2>Games</h2><div class="list">${rows || '<p class="small" style="padding:14px">No items yet. Run the passage engine or import content.</p>'}</div></section>
      <div class="two">
        <section class="sec"><h2 class="d-only">This week</h2><div class="card weekcard"><div class="days" aria-label="This week: ${w.active} of ${w.goal} days">${days}</div><div class="tot"><b>${w.active}/${w.goal}</b><span>days</span></div><p class="small">${w.active} of ${w.goal} days this week.${state.nav && state.nav.rest_weekday != null ? ` ${DAYS[state.nav.rest_weekday]} counts as on track.` : ''}</p></div></section>
        <section class="sec"><h2>So far</h2><div class="card counts"><div><b>${c.editions}</b><span>editions finished</span></div><div><b>${c.passages}</b><span>passages read</span></div><div><b>${c.arguments}</b><span>arguments weighed</span></div>
          <div><b>${c.answers}</b><span>answers</span></div><div><b>${c.minutes_spoken}</b><span>minutes spoken</span></div><div><b>${c.active_weeks}</b><span>active weeks</span></div></div></section>
      </div></div>`;
  main.querySelectorAll('[data-slot]').forEach(b => b.onclick = () => open(ed.slots[+b.dataset.slot]));
  main.querySelectorAll('[data-go2]').forEach(b => b.onclick = () => go(b.dataset.go2));
  ['cont', 'contTop'].forEach(id => { const b = $('#' + id); if (b && nextSlot) b.onclick = () => open(nextSlot); });
  const tp = $('#toPractice'); if (tp) tp.onclick = () => go('practice');
  if (recall) {
    $('#rcShow').onclick = () => {
      $('#rcShow').remove(); $('#rcT').readOnly = true;
      $('#rcOut').innerHTML = `<div class="ref"><span class="label">Yesterday's reference</span><q>${esc(ed.recall.reference)}</q>${(ed.recall.key_points || []).length ? `<ul>${ed.recall.key_points.map(k => `<li>${esc(k)}</li>`).join('')}</ul>` : ''}
        <span class="small">How much did you remember?</span><div class="btns">${['yes', 'partly', 'no'].map(m => `<button class="btn ghost" type="button" data-m="${m}">${m === 'yes' ? 'Got it' : m === 'partly' ? 'Partly' : 'Not really'}</button>`).join('')}</div></div>`;
      $('#rcOut').querySelectorAll('[data-m]').forEach(b => b.onclick = async () => { await api('/api/today/recall', { body: { answer: $('#rcT').value, mark: b.dataset.m } }); toast('Noted. On to today.'); $('#recall').remove(); });
    };
  }
}

// ── Practice ──

let practiceFilter = 'all';
async function practice() {
  const list = await api('/api/practice');
  const draw = () => {
    const shown = list.filter(g => practiceFilter === 'all' || PILLAR_OF[g.game] === practiceFilter);
    main.innerHTML = bar({ title: 'Practice', sub: isM3() ? '' : 'Extra rounds, any time' })
      + `<div class="body wide"><div class="headrow"><p class="lede">Anything beyond today's edition. The daily edition is the one that counts for the week.</p>
        <div class="seg" role="group" aria-label="Filter by skill">${[['all', 'All'], ['u', 'Understand'], ['r', 'Reason'], ['e', 'Express'], ['s', 'Speak']].map(([k, n]) => `<button type="button" data-f="${k}" aria-pressed="${practiceFilter === k}">${n}</button>`).join('')}</div></div>
        <div class="cards">${shown.map(g => { const p = PILLAR_OF[g.game]; return `<button class="gc" type="button" data-g="${g.game}" ${g.live ? '' : 'disabled'}>${sq(p)}<span class="mn">${g.minutes} min</span><b>${esc(g.name)}</b><span class="bl">${esc(g.blurb)}</span><span class="ct">${PILLAR[p]} · ${g.live ? `${g.live} ready` : 'none yet'}</span></button>`; }).join('')}</div></div>`;
    main.querySelectorAll('[data-f]').forEach(b => b.onclick = () => { practiceFilter = b.dataset.f; haptic('tick'); draw(); });
    main.querySelectorAll('[data-g]').forEach(b => b.onclick = async () => {
      try { const r = await api('/api/practice/' + b.dataset.g); location.hash = `play/${b.dataset.g}/${r.items.join(',')}`; }
      catch (e) { toast(e.message); }
    });
  };
  draw();
}

// ── Skills ──

function spark(vals) {
  if (!vals || vals.length < 2) return '<span class="small">A few more answers and a trend shows here.</span>';
  const W = 300, H = 26, n = vals.length;
  const pts = vals.map((v, i) => `${(i / (n - 1)) * W},${H - 3 - v * (H - 6)}`).join(' ');
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts}" style="fill:none;stroke:var(--accent);stroke-width:2;vector-effect:non-scaling-stroke"/></svg>`;
}

async function skills() {
  const s = await api('/api/skills');
  const order = ['gist', 'inference', 'weak', 'discern', 'precision', 'concision', 'fluency'];
  const d = s.discern;
  main.innerHTML = bar({ title: 'Skills', sub: isM3() ? '' : 'Your first try, unaided' })
    + `<div class="body"><p class="lede">Ratings measure your first try, unaided. They say "calibrating" until there's enough to go on.</p>
    <div class="list">${order.map(k => { const r = s.ratings[k]; const meta = s.skills[k];
      return `<div class="skill">${sq(meta.pillar)}<b>${esc(meta.name)}</b><span class="r">${r ? r.rating : '—'}${r && r.calibrating ? '<span class="chip">calibrating</span>' : ''}</span><div class="spark">${spark(s.recent[k])}</div></div>`; }).join('')}</div>
    <section class="sec"><h2>Fair or trick, honestly measured</h2>
    <div class="card">${d.dprime !== undefined ? `<p>Discernment <b>d′ ${d.dprime}</b> · bias ${d.bias > 0.15 ? 'toward calling things fair' : d.bias < -0.15 ? 'toward calling things tricks' : 'balanced'} (${d.bias})</p><p class="small" style="margin-top:4px">Caught ${Math.round(100 * d.hit_rate)}% of the tricks, flagged ${Math.round(100 * d.false_alarms)}% of the fair moves as tricks. ${d.brier != null ? `Confidence Brier score ${d.brier} (0 is perfect, 0.25 is a coin flip).` : ''}</p>` : `<p class="muted">After a few rounds of Technique or Fair Move, this shows whether you're getting sharper or just more suspicious.</p>`}</div></section>
    <section class="sec"><h2>How well you judge yourself</h2>
    <div class="card"><p class="muted">${s.self_gap != null ? `Your self-rating is off from the grade by <b>${s.self_gap}</b> points on average (on 0–4). Watch it shrink.` : 'Rate yourself before each verdict, and this tracks the gap.'}</p></div></section>
    <section class="sec"><h2>Away from practice</h2>
    <div class="list"><button class="li" type="button" id="bm"><span class="sq r">${icon('bench')}</span><span class="li-t"><b>The monthly benchmark</b><small>A sealed test, about 35 minutes. The honest measure of whether practice transfers.</small></span><span class="li-r">${s.bench_due ? '<span class="badge">Due</span>' : ''}${icon('chev', 'chev')}</span></button></div></section></div>`;
  $('#bm').onclick = () => go('bench');
}

// ── Golden set ──

async function golden() {
  const g = await api('/api/golden');
  const r = g.report;
  const rows = Object.entries(r.games).map(([game, v]) => Object.entries(v.criteria).map(([c, x]) => `<tr><td>${esc(game)}</td><td>${esc(c.replace('_', ' '))}</td><td class="n">${x.n || 0}</td><td class="n">${x.n ? Math.round(100 * x.exact) + '%' : '—'}</td><td class="n">${x.n ? Math.round(100 * x.within1) + '%' : '—'}</td><td class="n">${x.n ? (x.lenient > 0 ? '+' : '') + x.lenient : '—'}</td><td class="n">${x.qwk ?? '—'}</td></tr>`).join('')).join('');
  const GN = { gist: 'Gist & Infer', subtext: 'Subtext', bloat: 'Cut the Bloat' };
  main.innerHTML = bar({ title: 'Golden set', sub: isM3() ? '' : `${r.total} of ${r.target} scored by you` })
    + `<div class="body"><p class="lede">Answer an item, then score your own answer with the same rubric Claude uses. Fifty of these tell you whether its grades deserve your trust.</p>
    <div class="card"><div style="display:flex;justify-content:space-between;align-items:baseline"><b style="font-size:22px">${r.total} of ${r.target}</b><span class="small">scored by you</span></div><div class="bar8" style="margin-top:10px"><i style="width:${Math.min(100, 100 * r.total / r.target)}%"></i></div></div>
    <section class="sec"><h2>Score one now</h2>
    ${g.next.length ? `<div class="list">${g.next.map(id => { const gm = id.split(':')[0]; return `<button class="li" type="button" data-id="${esc(id)}">${sq(PILLAR_OF[gm] || 'u')}<span class="li-t"><b>${esc(GN[gm] || gm)}</b><small>Answer it, then grade yourself</small></span><span class="li-r"><span class="d-only">2 min</span>${icon('chev', 'chev')}</span></button>`; }).join('')}</div>` : '<p class="muted">No items left to score in these games.</p>'}</section>
    <section class="sec"><h2>How Claude agrees with you</h2>
    <div class="card" style="overflow-x:auto"><table class="tbl"><thead><tr><th>Game</th><th>Criterion</th><th>n</th><th>Exact</th><th>±1</th><th>Lenient</th><th>QWK</th></tr></thead><tbody>${rows}</tbody></table>
    <p class="small" style="margin-top:8px">Claude grades golden answers blind (without your anchors). "Lenient" above zero means it scores higher than you do. QWK of 0.6–0.7 is typical for open judgments; above 0.8 is very good.</p></div></section>
    ${g.disputed.length ? `<section class="sec"><h2>Grades you disputed</h2>${g.disputed.map(a => `<div class="card"><b>${esc(a.game)}</b> · ${a.score != null ? Math.round(100 * a.score) + '%' : '—'}<p class="small">${esc(a.disputed)}</p></div>`).join('')}</section>` : ''}</div>`;
  main.querySelectorAll('[data-id]').forEach(b => b.onclick = () => { location.hash = 'gold/' + b.dataset.id; });
}

// ── Settings ──

async function settings() {
  const s = await api('/api/settings');
  main.innerHTML = bar({ title: 'Settings' }) + `<div class="body">
    <section class="sec"><h2>Rhythm</h2>
    <form class="form card" id="sf">
      <label>Days a week I aim for<select class="inp" id="wg">${[1, 2, 3, 4, 5, 6, 7].map(n => `<option ${s.weekly_goal_days === n ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
      <label>Rest day (counts as on track)<select class="inp" id="rd"><option value="">None</option>${DAYS.map((d, i) => `<option value="${i}" ${s.rest_weekday === i ? 'selected' : ''}>${d}</option>`).join('')}</select></label>
      <label>How Claude talks to me<select class="inp" id="tone">${['soft', 'balanced', 'strict'].map(t => `<option ${s.grading_tone === t ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
      <button class="btn" type="submit">Save</button></form></section>
    <section class="sec"><h2>Password</h2>
    <form class="form card" id="pf"><label>Current password<input class="inp" id="cp" type="password" autocomplete="current-password"></label>
      <label>New password (10+ characters)<input class="inp" id="np" type="password" autocomplete="new-password"></label><button class="btn ghost" type="submit">Change password</button><p class="err" id="perr" hidden></p></form></section>
    <button class="btn link" id="out" type="button" style="margin:0 auto">Sign out</button></div>`;
  $('#sf').onsubmit = async e => { e.preventDefault(); await api('/api/settings', { body: { weekly_goal_days: +$('#wg').value, rest_weekday: $('#rd').value === '' ? null : +$('#rd').value, grading_tone: $('#tone').value } }); toast('Saved'); refreshNav('settings'); };
  $('#pf').onsubmit = async e => { e.preventDefault(); try { await api('/api/account', { body: { current: $('#cp').value, password: $('#np').value } }); toast('Password changed. Other browsers are signed out.'); $('#pf').reset(); } catch (err) { const el = $('#perr'); el.hidden = false; el.textContent = err.message; } };
  $('#out').onclick = async () => { await api('/api/logout', { body: {} }); state.me = null; signin(); };
}

// ── what native shells call (docs/SHELL.md) ──
window.binahCommand = name => {
  const [verb, arg] = String(name).split(':');
  if (verb === 'go' && arg) { go(arg); return true; }
  if (verb === 'back') return window.binahBack();
  if (verb === 'reload') { location.reload(); return true; }
  return false;
};
window.binahState = () => ({ route: state.route, signedIn: !!(state.me && state.me.signed_in),
  done: state.today ? state.today.edition.slots.filter(s => s.done).length : null,
  total: state.today ? state.today.edition.slots.length : null, canBack: !!state.back || state.route !== 'today' });
window.binahBack = () => {
  if (state.back) { const f = state.back; state.back = null; f(); return true; }
  if (state.route && state.route !== 'today' && state.route !== 'signin') { history.length > 1 ? history.back() : go('today'); return true; }
  return false;
};

if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('/sw.js').catch(() => {});
boot();
