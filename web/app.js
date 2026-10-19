// Binah's web client: routing, Today, Practice, Skills, the golden set, Settings, sign-in.
// The games themselves are in play.js. Native shells talk to the page through shell.js.
import { play, goldenPlay } from './play.js';
import { bench } from './bench.js';
import './shell.js';

export const $ = (s, el = document) => el.querySelector(s);
export const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const words = t => (String(t || '').trim().match(/\S+/g) || []).length;
const main = $('#main');

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

const ICONS = {
  today: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="4" y="5" width="16" height="15" rx="2.5"/><path d="M4 9.5h16M9 3v4M15 3v4"/></svg>',
  practice: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M5 19V9l7-5 7 5v10"/><path d="M9 19v-6h6v6"/></svg>',
  skills: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 19h16M7 16v-5M12 16V6M17 16v-8"/></svg>',
  golden: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 3l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.4 6.8 19.2l1-5.9L3.5 9.2l5.9-.8z"/></svg>',
  settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.4-2.3.9a7 7 0 0 0-2-1.2L14 3h-4l-.6 2.6a7 7 0 0 0-2 1.2l-2.3-.9-2 3.4 2 1.5a7 7 0 0 0 0 2.4l-2 1.5 2 3.4 2.3-.9a7 7 0 0 0 2 1.2L10 21h4l.6-2.6a7 7 0 0 0 2-1.2l2.3.9 2-3.4-2-1.5c.1-.4.1-.8.1-1.2z"/></svg>',
};
const TABS = [['today', 'Today'], ['practice', 'Practice'], ['skills', 'Skills'], ['golden', 'Golden set'], ['settings', 'Settings']];

function chrome(on, current) {
  $('#rail').hidden = !on; $('#tabbar').hidden = !on;
  if (!on) return;
  const mk = ([k, n]) => `<button type="button" data-go="${k}" ${current === k ? 'aria-current="page"' : ''}>${ICONS[k]}<span>${n}</span></button>`;
  $('#nav').innerHTML = TABS.map(mk).join('');
  $('#tabbar').innerHTML = TABS.filter(t => t[0] !== 'settings').map(mk).join('');
  document.querySelectorAll('[data-go]').forEach(b => b.onclick = () => { haptic('tick'); go(b.dataset.go); });
}

export const state = { route: 'today', me: null, today: null, back: null };
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
  if (route === 'play') { chrome(true, 'practice'); return play(rest[0], rest[1] ? rest[1].split(',') : null, { day: rest[2] || null, slot: rest[3] ?? null }); }
  if (route === 'gold') { chrome(true, 'golden'); return goldenPlay(rest[0]); }
  if (route === 'bench') { chrome(true, 'skills'); return bench(rest); }
  chrome(true, route);
  try {
    if (route === 'practice') return await practice();
    if (route === 'skills') return await skills();
    if (route === 'golden') return await golden();
    if (route === 'settings') return await settings();
    return await today();
  } catch (e) { if (e.message !== 'signed out') main.innerHTML = `<p class="err">${esc(e.message)}</p>`; }
}

// ── Today ──

const PILLAR = { u: 'Understand', r: 'Reason', e: 'Express', s: 'Speak' };
const LETTER = { u: 'U', r: 'R', e: 'E', s: 'S' };

function weekDots(w) {
  return `<div class="week" aria-label="This week: ${w.active} of ${w.goal} days">${w.days.map(d => `<i class="${d.answers ? 'on' : ''} ${d.rest ? 'rest' : ''} ${d.today ? 'today' : ''} ${d.future ? 'future' : ''}" title="${d.day}"></i>`).join('')}</div>`;
}

async function today() {
  const t = state.today = await api('/api/today');
  const ed = t.edition;
  const d = new Date(ed.day + 'T12:00:00');
  const done = ed.slots.filter(s => s.done).length;
  const mins = ed.slots.reduce((a, s) => a + (s.done ? 0 : s.minutes), 0);
  const rows = ed.slots.map(s => {
    const g = t.games[s.game];
    const st = s.done ? `<span class="st ok">${s.scores.length > 1 ? `${Math.round(100 * avg(s.scores.filter(x => x != null)))}%` : s.scores[0] != null ? Math.round(100 * s.scores[0]) + '%' : 'done'}</span>`
      : s.answered ? `<span class="st wait">${s.answered}/${s.items.length}</span>` : `<span class="st">${g.minutes} min</span>`;
    return `<button class="row ${s.done ? 'done' : ''}" type="button" data-slot="${s.slot}"><span class="ico ${s.pillar}">${LETTER[s.pillar]}</span><span><b>${esc(g.name)}</b><small>${esc(PILLAR[s.pillar])}${s.source ? ' · ' + esc(s.source) : ''}</small></span>${st}</button>`;
  }).join('');
  const recall = ed.recall && !ed.recall.mark ? `<div class="card" id="recall"><span class="label">Before you start</span><p style="margin-top:6px">Yesterday you read a passage${ed.recall.book ? ` from <b>${esc(ed.recall.book)}</b>` : ''}. What was its point?</p>
      <textarea class="ta" id="rcT" style="min-height:64px;margin-top:8px" aria-label="What you remember"></textarea><button class="btn ghost" id="rcShow" type="button">Check against yesterday's reference</button><div id="rcOut"></div></div>` : '';
  main.innerHTML = `<div class="top"><div><span class="mark"><b>binah</b><span class="he" lang="he">בינה</span></span>
      <div class="date" style="margin-top:12px">${d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}</div>
      <h1 class="title">Today's edition</h1><p class="sub">${ed.finished ? 'Done for today' : `About ${Math.max(1, mins)} minutes · ${done} of ${ed.slots.length} done`}</p></div>
      <div style="display:grid;justify-items:end;gap:6px;padding-top:4px">${weekDots(t.week)}<span class="small">${t.week.active} of ${t.week.goal} days this week</span></div></div>
    ${recall}
    <div class="sec">${rows || '<p class="muted">No items yet. Run the passage engine or import content.</p>'}</div>
    ${ed.finished ? `<div class="banner"><b>Today's edition is done.</b><span class="muted">Tomorrow opens with a recall card on today's passage. Anything else today is extra, in Practice.</span></div>` : ''}
    <div class="sec"><span class="label">So far</span></div>
    <div class="counts"><div><b>${t.counts.editions}</b><span>editions finished</span></div><div><b>${t.counts.passages}</b><span>passages read</span></div><div><b>${t.counts.arguments}</b><span>arguments weighed</span></div>
      <div><b>${t.counts.answers}</b><span>answers</span></div><div><b>${t.counts.minutes_spoken}</b><span>minutes spoken</span></div><div><b>${t.counts.active_weeks}</b><span>active weeks</span></div></div>`;
  main.querySelectorAll('[data-slot]').forEach(b => b.onclick = () => {
    const s = ed.slots[+b.dataset.slot];
    haptic('tick');
    location.hash = `play/${s.game}/${s.items.join(',')}/${ed.day}/${s.slot}`;
  });
  if (recall) {
    $('#rcShow').onclick = () => {
      $('#rcShow').remove(); $('#rcT').readOnly = true;
      $('#rcOut').innerHTML = `<div class="ref"><span class="label">Yesterday's reference</span><q>${esc(ed.recall.reference)}</q>${(ed.recall.key_points || []).length ? `<ul>${ed.recall.key_points.map(k => `<li>${esc(k)}</li>`).join('')}</ul>` : ''}
        <span class="small">How much did you remember?</span><div class="btns" style="grid-template-columns:repeat(3,1fr)">${['yes', 'partly', 'no'].map(m => `<button class="btn ghost" type="button" data-m="${m}">${m === 'yes' ? 'Got it' : m === 'partly' ? 'Partly' : 'Not really'}</button>`).join('')}</div></div>`;
      $('#rcOut').querySelectorAll('[data-m]').forEach(b => b.onclick = async () => { await api('/api/today/recall', { body: { answer: $('#rcT').value, mark: b.dataset.m } }); toast('Noted. On to today.'); $('#recall').remove(); });
    };
  }
}
const avg = a => a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0;

// ── Practice ──

async function practice() {
  const list = await api('/api/practice');
  const pill = { gist: 'u', subtext: 'u', weak: 'r', tech: 'r', word: 'e', bloat: 'e', jam: 's' };
  main.innerHTML = `<div class="top"><div><h1 class="title">Practice</h1><p class="sub">Extra rounds, any time. The daily edition is the one that counts for the week.</p></div></div>
    ${list.map(g => `<button class="row" type="button" data-g="${g.game}" ${g.live ? '' : 'disabled'}><span class="ico ${pill[g.game]}">${LETTER[pill[g.game]]}</span><span><b>${esc(g.name)}</b><small>${esc(g.blurb)}</small></span><span class="st">${g.live ? g.live + ' ready' : 'none yet'}</span></button>`).join('')}`;
  main.querySelectorAll('[data-g]').forEach(b => b.onclick = async () => {
    try { const r = await api('/api/practice/' + b.dataset.g); location.hash = `play/${b.dataset.g}/${r.items.join(',')}`; }
    catch (e) { toast(e.message); }
  });
}

// ── Skills ──

function spark(vals) {
  if (!vals || vals.length < 2) return '<span class="small">A few more answers and a trend shows here.</span>';
  const W = 300, H = 28, n = vals.length;
  const pts = vals.map((v, i) => `${(i / (n - 1)) * W},${H - 3 - v * (H - 6)}`).join(' ');
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts}" style="fill:none;stroke:var(--accent);stroke-width:2;vector-effect:non-scaling-stroke"/></svg>`;
}

async function skills() {
  const s = await api('/api/skills');
  const order = ['gist', 'inference', 'weak', 'discern', 'precision', 'concision', 'fluency'];
  const d = s.discern;
  main.innerHTML = `<div class="top"><div><h1 class="title">Skills</h1><p class="sub">Ratings measure your first try, unaided. They say "calibrating" until there's enough to go on.</p></div></div>
    ${order.map(k => { const r = s.ratings[k]; const meta = s.skills[k];
      return `<div class="skill"><b><span class="chip" style="margin-right:6px">${LETTER[meta.pillar]}</span>${esc(meta.name)}</b><span class="r">${r ? r.rating : '—'}${r && r.calibrating ? ' <span class="chip">calibrating</span>' : ''}</span><div class="spark">${spark(s.recent[k])}</div></div>`; }).join('')}
    <div class="sec"><span class="label">Fair or trick, honestly measured</span></div>
    <div class="card">${d.dprime !== undefined ? `<p>Discernment <b>d′ ${d.dprime}</b> · bias ${d.bias > 0.15 ? 'toward calling things fair' : d.bias < -0.15 ? 'toward calling things tricks' : 'balanced'} (${d.bias})</p><p class="small">Caught ${Math.round(100 * d.hit_rate)}% of the tricks, flagged ${Math.round(100 * d.false_alarms)}% of the fair moves as tricks. ${d.brier != null ? `Confidence Brier score ${d.brier} (0 is perfect, 0.25 is a coin flip).` : ''}</p>` : `<p class="muted">After a few rounds of Technique or Fair Move, this shows whether you're getting sharper or just more suspicious.</p>`}</div>
    <div class="sec"><span class="label">How well you judge yourself</span></div>
    <div class="card"><p class="muted">${s.self_gap != null ? `Your self-rating is off from the grade by <b>${s.self_gap}</b> points on average (on 0–4). Watch it shrink.` : 'Rate yourself before each verdict, and this tracks the gap.'}</p></div>
    <div class="sec"><span class="label">Away from practice</span></div>
    <button class="row" type="button" id="bm"><span class="ico r">B</span><span><b>The monthly benchmark</b><small>A sealed test, about 35 minutes. The honest measure of whether practice transfers.</small></span><span class="st">${s.bench_due ? 'due' : ''}</span></button>`;
  $('#bm').onclick = () => go('bench');
}

// ── Golden set ──

async function golden() {
  const g = await api('/api/golden');
  const r = g.report;
  const rows = Object.entries(r.games).map(([game, v]) => Object.entries(v.criteria).map(([c, x]) => `<tr><td>${esc(game)}</td><td>${esc(c)}</td><td class="n">${x.n || 0}</td><td class="n">${x.n ? Math.round(100 * x.exact) + '%' : '—'}</td><td class="n">${x.n ? Math.round(100 * x.within1) + '%' : '—'}</td><td class="n">${x.n ? (x.lenient > 0 ? '+' : '') + x.lenient : '—'}</td><td class="n">${x.qwk ?? '—'}</td></tr>`).join('')).join('');
  main.innerHTML = `<div class="top"><div><h1 class="title">Golden set</h1><p class="sub">Answer an item, then score your own answer with the same rubric Claude uses. Fifty of these tell you whether its grades deserve your trust.</p></div></div>
    <div class="card"><div style="display:flex;justify-content:space-between;align-items:baseline"><b style="font:600 22px var(--serif)">${r.total} of ${r.target}</b><span class="small">scored by you</span></div><div class="bar" style="margin-top:8px"><i style="width:${Math.min(100, 100 * r.total / r.target)}%"></i></div></div>
    <div class="sec"><span class="label">Score one now</span></div>
    ${g.next.length ? g.next.map(id => `<button class="row" type="button" data-id="${esc(id)}"><span class="ico u">★</span><span><b>${esc(({ gist: 'Gist & Infer', subtext: 'Subtext', bloat: 'Cut the Bloat' })[id.split(':')[0]])}</b><small>Answer it, then grade yourself</small></span><span class="st">2 min</span></button>`).join('') : '<p class="muted">No items left to score in these games.</p>'}
    <div class="sec"><span class="label">How Claude agrees with you</span></div>
    <div class="card" style="overflow-x:auto"><table class="tbl"><thead><tr><th>Game</th><th>Criterion</th><th>n</th><th>Exact</th><th>±1</th><th>Lenient</th><th>QWK</th></tr></thead><tbody>${rows}</tbody></table>
    <p class="small" style="margin-top:8px">Claude grades golden answers blind (without your anchors). "Lenient" above zero means it scores higher than you do. QWK of 0.6–0.7 is typical for open judgments; above 0.8 is very good.</p></div>
    ${g.disputed.length ? `<div class="sec"><span class="label">Grades you disputed</span></div>${g.disputed.map(a => `<div class="card" style="margin-bottom:8px"><b>${esc(a.game)}</b> · ${a.score != null ? Math.round(100 * a.score) + '%' : '—'}<p class="small">${esc(a.disputed)}</p></div>`).join('')}` : ''}`;
  main.querySelectorAll('[data-id]').forEach(b => b.onclick = () => { location.hash = 'gold/' + b.dataset.id; });
}

// ── Settings ──

async function settings() {
  const s = await api('/api/settings');
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  main.innerHTML = `<div class="top"><div><h1 class="title">Settings</h1></div></div>
    <form class="form card" id="sf">
      <label>Days a week I aim for<select class="inp" id="wg">${[1, 2, 3, 4, 5, 6, 7].map(n => `<option ${s.weekly_goal_days === n ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
      <label>Rest day (counts as on track)<select class="inp" id="rd"><option value="">None</option>${days.map((d, i) => `<option value="${i}" ${s.rest_weekday === i ? 'selected' : ''}>${d}</option>`).join('')}</select></label>
      <label>How Claude talks to me<select class="inp" id="tone">${['soft', 'balanced', 'strict'].map(t => `<option ${s.grading_tone === t ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
      <button class="btn" type="submit">Save</button></form>
    <div class="sec"><span class="label">Password</span></div>
    <form class="form card" id="pf"><label>Current password<input class="inp" id="cp" type="password" autocomplete="current-password"></label>
      <label>New password (10+ characters)<input class="inp" id="np" type="password" autocomplete="new-password"></label><button class="btn ghost" type="submit">Change password</button><p class="err" id="perr" hidden></p></form>
    <button class="btn link" id="out" type="button">Sign out</button>`;
  $('#sf').onsubmit = async e => { e.preventDefault(); await api('/api/settings', { body: { weekly_goal_days: +$('#wg').value, rest_weekday: $('#rd').value === '' ? null : +$('#rd').value, grading_tone: $('#tone').value } }); toast('Saved'); };
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
