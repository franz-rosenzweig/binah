// The games. Every open answer runs in the same fixed order:
// answer (plus a 0-4 self-rating) -> Claude's verdict -> one revision -> the reference.
import { $, api, esc, words, toast, haptic, state, go, bar, icon, PILLAR_OF, PILLAR } from './app.js';

const main = document.getElementById('main');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const paras = t => String(t || '').split(/\n\s*\n/).map(p => `<p>${esc(p)}</p>`).join('');
const NAMES = { gist: 'Gist & Infer', subtext: 'Subtext', weak: 'Find the Weak Step', tech: 'Technique or Fair Move?', word: "The Author's Word", bloat: 'Cut the Bloat', jam: 'Just a Minute' };
const SKILL = { gist: 'Gist', inference: 'Inference', weak: 'Weak steps', discern: 'Fair or trick', precision: 'Precision', concision: 'Concision', fluency: 'Fluency' };
let ctx = {};

// The game's header: back, the game and where it sits (a toolbar on desktop, a top app bar on Material),
// with a small capsule on the right for progress (`prog` text, or `progHtml` markup).
function head(name, prog = '', progHtml = '') {
  const p = PILLAR_OF[ctx.game];
  const n = state.today ? state.today.edition.slots.length : 3;
  const where = ctx.day ? `game ${Number(ctx.slot) + 1} of ${n} in today's edition` : ctx.golden ? 'Golden set' : 'Practice';
  const cap = progHtml || (prog ? esc(prog) : '');
  return bar({ title: name, sub: `${p ? PILLAR[p] + ' · ' : ''}${where}`, back: true, kind: 'game', actions: cap ? `<span class="capsule" id="cap">${cap}</span>` : '' });
}
// Called after every render of a game screen: wraps what follows the header in the game body, and
// marks it split when it has a reading pane and an answer panel (side by side on a wide desktop window).
function bindX(onBack = leave) {
  const hd = main.querySelector(':scope > .bar');
  if (hd && !main.querySelector(':scope > .body')) {
    const body = document.createElement('div');
    body.className = 'body game';
    while (hd.nextSibling) body.appendChild(hd.nextSibling);
    main.appendChild(body);
  }
  const body = main.querySelector(':scope > .body');
  if (body) body.classList.toggle('split', !!body.querySelector('.gm'));
  const x = $('#barBack'); if (x) x.onclick = onBack;
  state.back = onBack;
}
function leave() { ctx.day ? go('today') : go('practice'); }
function srcLine(it) {
  const s = it.source || {};
  if (!s.book) return '';
  return `<div class="src"><span>From</span><b>${esc(s.book)}</b>${s.author ? `<span>${esc(s.author.split('&')[0].trim())}</span>` : ''}${s.highlighted ? '<span class="chip r">✎ you highlighted this</span>' : ''}</div>`;
}
function delta(a) {
  if (a.rating_before == null || a.rating_after == null) return '';
  const d = a.rating_after - a.rating_before;
  return `<div class="delta"><span>${esc(SKILL[a.skill] || a.skill)} <b>${a.rating_before} → ${a.rating_after}</b></span><em class="${d >= 0 ? 'up' : 'down'}">${d >= 0 ? '+' : ''}${d}</em></div>`;
}
const endBtns = () => `<div class="btns"><button class="btn ghost" type="button" data-next>${ctx.day ? 'Back to today' : 'Another one'}</button><button class="btn link" type="button" data-dispute>I think this grade is wrong</button></div>`;
function bindEnd(el, a) {
  const n = el.querySelector('[data-next]');
  if (n) n.onclick = () => ctx.day ? go('today') : nextPractice(a.game);
  const d = el.querySelector('[data-dispute]');
  if (d) d.onclick = async () => { await api(`/api/attempts/${a.id}/dispute`, { body: { note: 'disputed from the result screen' } }); d.textContent = 'Noted. It goes to your golden set.'; d.disabled = true; };
}
async function nextPractice(game) {
  try { const r = await api('/api/practice/' + game); location.hash = `play/${game}/${r.items.join(',')}`; }
  catch (e) { toast(e.message); go('practice'); }
}
async function waitFor(id, ok) {
  for (let i = 0; i < 200; i++) {
    const a = await api(`/api/attempts/${id}`);
    if (ok(a)) return a;
    await sleep(i < 10 ? 1500 : 3000);
  }
  return api(`/api/attempts/${id}`);
}
const waiting = text => `<div class="wait"><i></i><span>${esc(text)}</span></div>`;
const bandOf = s => s == null ? 'Graded' : s >= 0.85 ? 'Strong' : s >= 0.65 ? 'Solid' : s >= 0.4 ? 'Partial' : 'Missed';

export async function play(game, ids, where = {}) {
  ctx = { game, day: where.day, slot: where.slot === null ? null : Number(where.slot) };
  if (!ids || !ids.length) return go('practice');
  try {
    if (game === 'tech') return await techRound(ids);
    const it = await api('/api/item/' + encodeURIComponent(ids[0]));
    ({ gist: playGist, subtext: playSubtext, weak: playWeak, word: playWord, bloat: playBloat, jam: playJam })[game](it);
  } catch (e) { main.innerHTML = head(NAMES[game] || 'Binah') + `<p class="err">${esc(e.message)}</p>`; bindX(); }
}

function selfRate(id) {
  return `<p class="ask">How sure are you? Rate it before the verdict.</p><div class="rate5" id="${id}" role="group" aria-label="Self rating">${[0, 1, 2, 3, 4].map(n => `<button class="opt" type="button" data-n="${n}">${n}</button>`).join('')}</div>`;
}
function bindRate(id, onPick) {
  const el = $('#' + id);
  el.onclick = e => { const b = e.target.closest('button'); if (!b) return; [...el.children].forEach(x => x.classList.toggle('on', x === b)); haptic('tick'); onPick(+b.dataset.n); };
}
async function submit(item_id, answer, self_rating, started) {
  return api('/api/attempts', { body: { item_id, answer, self_rating, ms: Date.now() - started, day: ctx.day, slot: ctx.slot } });
}

// open-answer verdict, shared by gist, subtext and bloat
function verdictHTML(a, g, second) {
  const score = second ? a.score2 : a.score;
  const crit = g ? Object.entries(g).filter(([k, v]) => Number.isInteger(v) && !['covered'].includes(k)) : [];
  return `<div class="verdict"><div class="top2"><span class="band">${bandOf(score)}${second ? ' · revised' : ''}</span>${a.self_rating != null && !second ? `<span class="small">you said ${a.self_rating}/4</span>` : ''}</div>
    ${crit.length ? `<div class="crit">${crit.map(([k, v]) => `<span class="chip">${esc(k.replace('_', ' '))} ${v}/4</span>`).join('')}</div>` : ''}
    ${g.strength ? `<span class="plus"><b>+</b> ${esc(g.strength)}</span>` : ''}${g.work_on ? `<span class="minus"><b>→</b> ${esc(g.work_on)}</span>` : ''}
    ${!second && g.hint ? `<span class="small">Hint: ${esc(g.hint)}</span>` : ''}</div>`;
}

async function openFlow({ a, out, field, onReference, reviseWith }) {
  // a: attempt just created (status grading). out: element to render into.
  out.innerHTML = waiting('Claude is reading it against the hidden key…');
  a = await waitFor(a.id, x => x.status !== 'grading');
  if (a.status === 'later') {
    out.innerHTML = `<div class="verdict"><span class="band">Grading later</span><span class="muted">Claude couldn't grade this right now. It will, and the score lands in your history.</span></div><button class="btn ghost" type="button" id="refBtn">Show the reference</button>`;
    $('#refBtn').onclick = async () => { const r = await api(`/api/attempts/${a.id}/reveal`, { body: {} }); onReference(r, out); };
    return;
  }
  haptic(a.score >= 0.65 ? 'confirm' : 'reject');
  out.innerHTML = verdictHTML(a, a.grade || {}, false) + delta(a)
    + `<div class="btns"><button class="btn" type="button" id="revBtn">Revise once</button><button class="btn ghost" type="button" id="refBtn">Keep it, show the reference</button></div>`;
  $('#refBtn').onclick = async () => { const r = await api(`/api/attempts/${a.id}/reveal`, { body: {} }); onReference(r, out); };
  $('#revBtn').onclick = () => {
    reviseWith(async answer => {
      out.innerHTML = waiting('Claude is reading the revision…');
      await api(`/api/attempts/${a.id}/revise`, { body: { answer } });
      const r = await waitFor(a.id, x => x.grade2 || x.status === 'later');
      out.innerHTML = r.grade2 ? verdictHTML(r, r.grade2, true) + delta(r) : '';
      onReference(r, out, true);
    });
  };
}

// ── Gist & Infer ──
function playGist(it) {
  const started = Date.now();
  main.innerHTML = head(NAMES.gist, 'Read') + srcLine(it) + `<div class="passage">${paras(it.passage)}</div>
    <button class="btn" id="hide" type="button">I've got it, hide the passage</button><p class="small" style="margin-top:8px;text-align:center">Read at your own pace. Rereading is fine.</p>`;
  bindX();
  $('#hide').onclick = () => {
    window.scrollTo(0, 0);
    let self = null;
    main.innerHTML = head(NAMES.gist, 'Write') + `<p class="ask">What's the main point? 20 words or fewer, from memory.</p>
      <textarea class="ta" id="gT" aria-label="Your gist" autocapitalize="sentences"></textarea><div class="meter"><span>the point, not the topic</span><span id="gW">0 / 20</span></div>
      <p class="ask">${esc(it.inference_q)}</p><textarea class="ta" id="gI" style="min-height:70px" aria-label="Your answer"></textarea>
      ${selfRate('gR')}<button class="btn" id="send" type="button" disabled>Send to the grader</button><div id="out"></div>`;
    bindX();
    const upd = () => { const n = words($('#gT').value); $('#gW').textContent = `${n} / 20`; $('#gW').className = n > 20 ? 'bad' : ''; $('#send').disabled = !n || n > 20 || self === null; };
    $('#gT').oninput = upd;
    bindRate('gR', n => { self = n; upd(); });
    $('#send').onclick = async () => {
      $('#send').remove(); $('#gT').readOnly = true; $('#gI').readOnly = true;
      const a = await submit(it.id, { gist: $('#gT').value.trim(), inference: $('#gI').value.trim() }, self, started);
      openFlow({ a, out: $('#out'),
        reviseWith: done => { $('#gT').readOnly = false; $('#gT').focus(); $('#out').innerHTML = `<button class="btn" id="send2" type="button">Send the revision</button>`; $('#send2').onclick = () => { if (words($('#gT').value) > 20) return toast('Keep it to 20 words'); $('#gT').readOnly = true; done({ gist: $('#gT').value.trim(), inference: $('#gI').value.trim() }); }; },
        onReference: (r, out) => {
          const k = r.key || {}; const cov = new Set(((r.grade2 || r.grade || {}).covered) || []);
          out.insertAdjacentHTML('beforeend', `<div class="ref"><span class="label">The reference</span><q>${esc(k.gist)}</q><ul>${(k.key_points || []).map((p, i) => `<li class="${cov.has(i + 1) ? 'got' : 'miss'}">${cov.has(i + 1) ? '✓ ' : ''}${esc(p)}</li>`).join('')}</ul><span><b>The inference:</b> ${esc(k.inference_a)}</span></div>` + endBtns());
          bindEnd(out, r);
        } });
    };
  };
}

// ── Subtext ──
function playSubtext(it) {
  const started = Date.now(); let self = null;
  main.innerHTML = head(NAMES.subtext) + `<div class="gm"><div class="pane">${srcLine(it)}<div class="passage">${paras(it.passage)}</div></div><aside class="insp" aria-label="Your answer"><p class="ask">${esc(it.question)}</p>
    <textarea class="ta" id="sT" style="min-height:80px" aria-label="Your answer"></textarea>${selfRate('sR')}<button class="btn" id="send" type="button" disabled>Send to the grader</button><div id="out"></div></aside></div>`;
  bindX();
  const upd = () => { $('#send').disabled = !$('#sT').value.trim() || self === null; };
  $('#sT').oninput = upd; bindRate('sR', n => { self = n; upd(); });
  $('#send').onclick = async () => {
    $('#send').remove(); $('#sT').readOnly = true;
    const a = await submit(it.id, { text: $('#sT').value.trim() }, self, started);
    openFlow({ a, out: $('#out'),
      reviseWith: done => { $('#sT').readOnly = false; $('#sT').focus(); $('#out').innerHTML = `<button class="btn" id="send2" type="button">Send the revision</button>`; $('#send2').onclick = () => { $('#sT').readOnly = true; done({ text: $('#sT').value.trim() }); }; },
      onReference: (r, out) => { const k = r.key || {}; out.insertAdjacentHTML('beforeend', `<div class="ref"><span class="label">What's going on</span><span>${esc(k.answer)}</span><span class="small">It shows in: <q>${esc(k.evidence_quote)}</q></span></div>` + endBtns()); bindEnd(out, r); } });
  };
}

// ── Cut the Bloat ──
function playBloat(it) {
  const started = Date.now(); let self = null;
  main.innerHTML = head(NAMES.bloat, `par ${it.par}`) + srcLine(it) + `<p class="ask">Someone padded a good writer's sentence. Cut it back without changing what it says. Par is the author's own word count.</p>
    <textarea class="ta" id="bT" style="min-height:140px" aria-label="Your cut">${esc(it.padded)}</textarea><div class="meter"><span id="bN"></span><span id="bL"></span></div>
    ${selfRate('bR')}<button class="btn" id="send" type="button" disabled>Putt</button><div id="out"></div>`;
  bindX();
  const golf = d => d <= -2 ? 'Eagle' : d === -1 ? 'Birdie' : d === 0 ? 'Par' : d === 1 ? 'Bogey' : d === 2 ? 'Double bogey' : '+' + d;
  const upd = () => { const n = words($('#bT').value), d = n - it.par; $('#bN').textContent = `${n} words · par ${it.par}`; $('#bL').textContent = golf(d); $('#bL').className = d <= 0 ? 'good' : d > 2 ? 'bad' : ''; $('#send').disabled = !n || self === null; };
  $('#bT').oninput = upd; upd(); bindRate('bR', n => { self = n; upd(); });
  $('#send').onclick = async () => {
    $('#send').remove(); $('#bT').readOnly = true;
    const a = await submit(it.id, { text: $('#bT').value.trim() }, self, started);
    openFlow({ a, out: $('#out'),
      reviseWith: done => { $('#bT').readOnly = false; $('#bT').focus(); $('#out').innerHTML = `<button class="btn" id="send2" type="button">Putt again</button>`; $('#send2').onclick = () => { $('#bT').readOnly = true; done({ text: $('#bT').value.trim() }); }; },
      onReference: (r, out) => { const k = r.key || {}; const ins = r.instant || {}; out.insertAdjacentHTML('beforeend', `<div class="ref"><span class="label">The author's line · ${it.par} words</span><q>${esc(k.original)}</q>${ins.golf ? `<span class="small">You: ${ins.words} words, ${esc(ins.golf)}</span>` : ''}</div>` + endBtns()); bindEnd(out, r); } });
  };
}

// ── Find the Weak Step ──
function playWeak(it) {
  const started = Date.now(); let pick = null, flaw = null;
  main.innerHTML = head(NAMES.weak) + `<div class="gm"><div class="pane">${srcLine(it)}<p class="ask">Tap the sentence where the reasoning is weakest, or call it sound.</p>
    <div class="passage" id="wp">${it.sentences.map((s, i) => s === '¶' ? '<br><br>' : `<span class="sent" role="button" tabindex="0" data-i="${i}">${esc(s)}</span> `).join('')}</div></div>
    <aside class="insp" aria-label="Your answer"><p class="ask">What's wrong with it?</p><div class="pills" id="wf">${it.flaws.map(f => `<button class="opt" type="button" data-f="${esc(f)}">${esc(f)}</button>`).join('')}</div>
    <p class="ask">Why, in one line? (optional; Claude reads it)</p><textarea class="ta" id="why" style="min-height:60px" aria-label="Why"></textarea>
    <button class="btn" id="send" type="button" disabled>Check Answer</button><div id="out"></div></aside></div>`;
  bindX();
  const upd = () => { $('#send').disabled = flaw === null || (pick === null && flaw !== 'none (sound)'); };
  main.querySelectorAll('.sent').forEach(s => { const f = () => { if ($('#wp').classList.contains('locked')) return; pick = +s.dataset.i; main.querySelectorAll('.sent').forEach(x => x.classList.toggle('picked', x === s)); haptic('tick'); upd(); }; s.onclick = f; s.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); f(); } }; });
  $('#wf').onclick = e => { const b = e.target.closest('button'); if (!b || b.disabled) return; flaw = b.dataset.f; [...$('#wf').children].forEach(x => x.classList.toggle('on', x === b)); upd(); };
  $('#send').onclick = async () => {
    $('#send').remove(); $('#wp').classList.add('locked'); [...$('#wf').children].forEach(x => x.disabled = true); $('#why').readOnly = true;
    let a = await submit(it.id, { index: pick, flaw, why: $('#why').value.trim() }, null, started);
    const k = a.key || {}, ins = a.instant || {};
    if (ins.key_index != null) main.querySelector(`.sent[data-i="${ins.key_index}"]`)?.classList.add('key');
    if (pick != null && !ins.spot_ok) main.querySelector(`.sent[data-i="${pick}"]`)?.classList.add('miss');
    [...$('#wf').children].forEach(x => { if (x.dataset.f === k.flaw) x.classList.add('key'); else if (x.dataset.f === flaw) x.classList.add('miss'); });
    haptic(a.score >= 1 ? 'confirm' : 'reject');
    $('#out').innerHTML = `<div class="verdict"><div class="top2"><span class="band">${a.score >= 1 ? 'Clean' : a.score > 0 ? 'Half right' : 'Missed'}</span><span class="small">spot ${ins.spot_ok ? '✓' : '✗'} · flaw ${ins.flaw_ok ? '✓' : '✗'}</span></div>
      <span><b>${esc(k.flaw)}.</b> ${esc(k.explain)}</span><span><b>It quietly assumes:</b> ${esc(k.assumption)}</span><div id="whyOut"></div></div>${delta(a)}${endBtns()}`;
    bindEnd($('#out'), a);
    if ($('#why').value.trim()) {
      $('#whyOut').innerHTML = waiting('Claude is reading your reason…');
      a = await waitFor(a.id, x => x.grade);
      const g = a.grade || {};
      $('#whyOut').innerHTML = g.work_on ? `<span><b>Your reason:</b> ${g.reason ?? '?'}/4. ${esc(g.work_on)}</span>` : '';
    }
  };
}

// ── The Author's Word ──
function playWord(it) {
  const started = Date.now();
  const sentence = esc(it.sentence).replace('_____', '<span class="blank">&nbsp;</span>');
  main.innerHTML = head(NAMES.word) + `<div class="gm"><div class="pane">${srcLine(it)}<p class="passage" style="font-size:20px">${sentence}</p></div><aside class="insp" aria-label="Your answer"><p class="ask">Which word did the author choose?</p>
    <div class="opts" id="wo">${it.options.map(w => `<button class="opt" type="button" data-w="${esc(w)}">${esc(w)}</button>`).join('')}</div><div id="out"></div></aside></div>`;
  bindX();
  $('#wo').onclick = async e => {
    const b = e.target.closest('button'); if (!b || b.disabled) return;
    [...$('#wo').children].forEach(x => x.disabled = true);
    const a = await submit(it.id, { choice: b.dataset.w }, null, started);
    const k = a.key || {};
    [...$('#wo').children].forEach(x => { if (x.dataset.w === k.target) x.classList.add('key'); else if (x === b) x.classList.add('miss'); });
    haptic(a.score ? 'confirm' : 'reject');
    $('#out').innerHTML = `<div class="verdict"><span class="band">${a.score ? "The author's word" : `The author wrote "${esc(k.target)}"`}</span><span>${esc(k.why)}</span></div>${delta(a)}${endBtns()}`;
    bindEnd($('#out'), a);
  };
}

// ── Technique or Fair Move? (a round of six) ──
async function techRound(ids) {
  const results = [];
  for (let i = 0; i < ids.length; i++) {
    const it = await api('/api/item/' + encodeURIComponent(ids[i]));
    const r = await techOne(it, i, ids.length, results);
    if (!r) return;
    results.push(r);
  }
  const right = results.filter(r => r.instant.kind_ok).length;
  const briers = results.map(r => r.instant.brier).filter(b => b != null);
  let sk = null;
  try { sk = await api('/api/skills'); } catch { sk = null; }
  const d = sk && sk.discern;
  main.innerHTML = head(NAMES.tech, 'Done') + `<div class="verdict"><span class="band">${right} of ${results.length} called right</span>
    ${briers.length ? `<span>Confidence Brier score this round: <b>${(briers.reduce((a, b) => a + b, 0) / briers.length).toFixed(3)}</b> (0 is perfect, 0.25 is a coin flip).</span>` : ''}
    ${d && d.dprime !== undefined ? `<span>Over all your rounds: discernment d′ <b>${d.dprime}</b>, ${d.bias > 0.15 ? 'leaning toward calling things fair' : d.bias < -0.15 ? 'leaning toward calling things tricks' : 'no lean either way'}.</span>` : '<span class="small">After a few rounds, Skills shows whether you are getting sharper or just more suspicious.</span>'}</div>`
    + `<div class="btns"><button class="btn ghost" type="button" data-next>${ctx.day ? 'Back to today' : 'Another round'}</button></div>`;
  bindX();
  main.querySelector('[data-next]').onclick = () => ctx.day ? go('today') : nextPractice('tech');
}

function techOne(it, i, n, results) {
  return new Promise(resolve => {
    const started = Date.now(); let kind = null, tech = null;
    const prog = `<span class="prog" aria-label="${i + 1} of ${n}">${Array.from({ length: n }, (_, j) => `<i class="${j < results.length ? (results[j].instant.kind_ok ? 'ok' : 'no') : j === i ? 'on' : ''}"></i>`).join('')}</span>`;
    main.innerHTML = head(NAMES.tech, '', prog) + `<div class="gm"><div class="pane"><p class="small" style="margin:6px 0">${esc(it.context)}</p><div class="tech-text" id="tt">${esc(it.text)}</div></div>
      <aside class="insp" aria-label="Your call"><div class="tk"><button class="opt" type="button" data-k="technique">Manipulation</button><button class="opt" type="button" data-k="fair">Fair move</button></div>
      <div id="techPick" hidden><p class="ask">Which technique? (optional, a bonus if right)</p><div class="pills" id="tp">${it.techniques.map(t => `<button class="opt" type="button" data-t="${esc(t)}">${esc(t)}</button>`).join('')}</div></div>
      <div class="conf"><span>How sure are you?</span><b id="cv">70%</b></div><input type="range" id="cr" min="50" max="100" step="5" value="70" aria-label="Confidence">
      <button class="btn" id="send" type="button" disabled>Call It</button><div id="out"></div></aside></div>`;
    bindX();
    const kinds = [...main.querySelectorAll('[data-k]')];
    kinds.forEach(b => b.onclick = () => { if (b.disabled) return; kind = b.dataset.k; kinds.forEach(x => x.classList.toggle('on', x === b)); $('#techPick').hidden = kind !== 'technique'; $('#send').disabled = false; haptic('tick'); });
    $('#tp').onclick = e => { const b = e.target.closest('button'); if (!b || b.disabled) return; tech = tech === b.dataset.t ? null : b.dataset.t; [...$('#tp').children].forEach(x => x.classList.toggle('on', x.dataset.t === tech)); };
    $('#cr').oninput = () => { $('#cv').textContent = $('#cr').value + '%'; };
    $('#send').onclick = async () => {
      $('#send').remove(); kinds.forEach(x => x.disabled = true); [...$('#tp').children].forEach(x => x.disabled = true); $('#cr').disabled = true;
      const a = await submit(it.id, { kind, technique: kind === 'technique' ? tech : null, confidence: +$('#cr').value }, null, started);
      const k = a.key || {}, ins = a.instant || {};
      kinds.forEach(x => { if (x.dataset.k === k.kind) x.classList.add('key'); else if (x.dataset.k === kind) x.classList.add('miss'); });
      if (k.tell) { const t = $('#tt'); const idx = t.textContent.indexOf(k.tell); if (idx >= 0) t.innerHTML = esc(t.textContent.slice(0, idx)) + `<mark>${esc(k.tell)}</mark>` + esc(t.textContent.slice(idx + k.tell.length)); }
      haptic(ins.kind_ok ? 'confirm' : 'reject');
      $('#out').innerHTML = `<div class="verdict"><span class="band">${ins.kind_ok ? 'Right' : 'Not quite'} · ${k.kind === 'fair' ? 'a fair move' : esc(k.technique)}</span>${k.kind === 'fair' ? `<span class="small">It resembles ${esc(k.technique)}, done fairly.</span>` : ins.label_ok ? '<span class="small">And you named the technique.</span>' : ''}<span>${esc(k.why)}</span></div>
        <button class="btn" type="button" id="nx">${i + 1 < n ? 'Next' : 'See the round'}</button>`;
      $('#nx').onclick = () => resolve(a);
    };
  });
}

// ── Just a Minute ──
function playJam(it) {
  let rec = null, chunks = [], t0 = 0, timer = null, stream = null;
  main.innerHTML = head(NAMES.jam, '60 s') + `<section class="topiccard"><span>Your topic</span><p class="topic">${esc(it.topic)}</p></section>
    <div class="rec"><div class="ring"><svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="44" style="fill:none;stroke:var(--sunk);stroke-width:6"/><circle id="arc" cx="50" cy="50" r="44" style="fill:none;stroke:var(--accent);stroke-width:6;stroke-linecap:round;stroke-dasharray:276.5;stroke-dashoffset:276.5"/></svg><span class="t" id="tm">1:00</span></div>
      <div class="rules"><span>No hesitation</span><span>No repetition</span><span>No deviation</span></div>
      <button class="recbtn" id="rb" type="button" aria-label="Start recording">${icon('mic', 'mic')}${icon('stop', 'stop')}</button><span class="small" id="rs">Tap to start. It stops by itself at sixty seconds.</span></div><div id="out"></div>`;
  const stopAll = () => { if (timer) clearInterval(timer); timer = null; if (stream) stream.getTracks().forEach(t => t.stop()); };
  bindX(() => { if (rec && rec.state === 'recording') { rec.onstop = null; rec.stop(); window.binahShell?.mic?.(false); } stopAll(); leave(); });
  const finish = () => { if (rec && rec.state === 'recording') rec.stop(); };
  $('#rb').onclick = async () => {
    if (rec && rec.state === 'recording') return finish();
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } }); }
    catch { toast("Binah can't use the microphone. Allow it in the browser or app settings."); return; }
    const mime = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'].find(m => window.MediaRecorder && MediaRecorder.isTypeSupported(m)) || '';
    rec = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
    chunks = [];
    rec.ondataavailable = e => { if (e.data.size) chunks.push(e.data); };
    rec.onstop = async () => {
      stopAll();
      $('#rb').classList.remove('on'); $('#rb').disabled = true; $('#rs').textContent = 'Got it.';
      const cap = $('#cap'); if (cap) cap.outerHTML = '<span class="capsule" id="cap">Sent</span>';
      window.binahShell?.mic?.(false);
      const blob = new Blob(chunks, { type: rec.mimeType || 'audio/webm' });
      const fd = new FormData();
      fd.append('item_id', it.id); fd.append('day', ctx.day || ''); fd.append('slot', ctx.slot ?? -1); fd.append('ms', Date.now() - t0);
      fd.append('file', blob, 'answer.' + ((rec.mimeType || '').includes('mp4') ? 'mp4' : 'webm'));
      $('#out').innerHTML = waiting('Transcribing on the server, then Claude listens for deviation…');
      try {
        const a0 = await api('/api/audio', { body: fd });
        const a = await waitFor(a0.id, x => x.status !== 'grading');
        jamResult(a);
      } catch (e) { $('#out').innerHTML = `<p class="err">${esc(e.message)}</p>`; }
    };
    rec.start(1000); t0 = Date.now();
    window.binahShell?.mic?.(true);
    $('#rb').classList.add('on'); $('#rb').setAttribute('aria-label', 'Stop and send'); $('#rs').textContent = 'Stop sends it. Your voice goes only to your Binah server.'; haptic('confirm');
    const cap = $('#cap'); if (cap) cap.outerHTML = '<span class="recchip" id="cap"><i></i>Recording</span>';
    timer = setInterval(() => {
      const left = Math.max(0, 60 - (Date.now() - t0) / 1000), s = Math.ceil(left);
      $('#tm').textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      $('#arc').style.strokeDashoffset = String(276.5 * (left / 60));
      if (left <= 0) finish();
    }, 200);
  };
}

function jamResult(a) {
  const m = (a.instant || {}).metrics || (a.answer || {}).metrics || {};
  const g = a.grade || {}, ins = a.instant || {};
  const fmt = (v, d = 0) => v == null ? '—' : Number(v).toFixed(d);
  haptic(a.score >= 0.65 ? 'confirm' : 'reject');
  $('#out').innerHTML = `<div class="metrics"><div><b>${fmt(m.speaking_time)}s</b><span>speaking</span></div><div><b>${fmt(m.wpm)}</b><span>words a minute</span></div><div><b>${fmt(m.fillers_per_min, 1)}</b><span>fillers a minute</span></div>
      <div><b>${fmt(m.long_pauses)}</b><span>long pauses</span></div><div><b>${(m.repeats || []).length}</b><span>repeated words</span></div><div><b>${m.first_sentence_clean ? 'clean' : 'not yet'}</b><span>first sentence</span></div></div>
    <div class="verdict"><div class="top2"><span class="band">${a.status === 'later' ? 'Grading later' : bandOf(a.score)}</span><span class="small">hesitation ${ins.hesitation ?? '—'}/4 · repetition ${ins.repetition ?? '—'}/4 · deviation ${g.deviation ?? '—'}/4 · structure ${g.structure ?? '—'}/4</span></div>
      ${g.strength ? `<span class="plus"><b>+</b> ${esc(g.strength)}</span>` : ''}${g.work_on ? `<span class="minus"><b>→</b> ${esc(g.work_on)}</span>` : ''}
      ${(g.deviations || []).length ? `<span class="small">Wandered at: ${g.deviations.map(d => `<q>${esc(d)}</q>`).join(', ')}</span>` : ''}
      ${(m.repeats || []).length ? `<span class="small">Said more than twice: ${m.repeats.map(r => `${esc(r.word)} ×${r.count}`).join(', ')}</span>` : ''}</div>
    ${delta(a)}<details class="card" style="margin-top:10px"><summary class="small" style="cursor:pointer">What you said</summary><p class="transcript" style="margin-top:8px">${esc((a.answer || {}).text || '')}</p></details>${endBtns()}`;
  bindEnd($('#out'), a);
}

// ── golden set: answer, see the key, then score yourself with the rubric ──
export async function goldenPlay(id) {
  const [it, g] = await Promise.all([api('/api/item/' + encodeURIComponent(id)), api('/api/golden')]);
  const rubric = g.rubrics[it.game].criteria;
  ctx = { game: it.game, golden: true };
  state.back = () => go('golden');
  let field;
  if (it.game === 'gist') {
    main.innerHTML = head('Golden set · ' + NAMES.gist) + srcLine(it) + `<div class="passage">${paras(it.passage)}</div><button class="btn" id="hide" type="button">Hide it and write</button>`;
    bindX(() => go('golden'));
    await new Promise(r => { $('#hide').onclick = r; });
    main.innerHTML = head('Golden set · ' + NAMES.gist) + `<p class="ask">The main point, 20 words or fewer.</p><textarea class="ta" id="aT"></textarea><p class="ask">${esc(it.inference_q)}</p><textarea class="ta" id="aI" style="min-height:64px"></textarea>`;
    field = () => ({ gist: $('#aT').value.trim(), inference: $('#aI').value.trim() });
  } else if (it.game === 'subtext') {
    main.innerHTML = head('Golden set · ' + NAMES.subtext) + srcLine(it) + `<div class="passage">${paras(it.passage)}</div><p class="ask">${esc(it.question)}</p><textarea class="ta" id="aT"></textarea>`;
    field = () => ({ text: $('#aT').value.trim() });
  } else {
    main.innerHTML = head('Golden set · ' + NAMES.bloat) + `<p class="ask">Cut it back to the author's line (par ${it.par}).</p><textarea class="ta" id="aT" style="min-height:130px">${esc(it.padded)}</textarea>`;
    field = () => ({ text: $('#aT').value.trim() });
  }
  main.insertAdjacentHTML('beforeend', `<button class="btn" id="next" type="button">Now Score It Yourself</button><div id="sc"></div>`);
  bindX(() => go('golden'));
  $('#next').onclick = async () => {
    const answer = field();
    if (!Object.values(answer).some(Boolean)) return toast('Write an answer first');
    $('#next').remove(); main.querySelectorAll('textarea').forEach(t => t.readOnly = true);
    const mine = {};
    const kk = (await api('/api/golden/key/' + encodeURIComponent(it.id))).key || {};
    const keyHTML = `<div class="ref"><span class="label">The key</span><q>${esc(kk.gist || kk.answer || kk.original || '')}</q>${(kk.key_points || []).length ? `<ul>${kk.key_points.map(p => `<li>${esc(p)}</li>`).join('')}</ul>` : ''}${kk.inference_a ? `<span><b>Inference:</b> ${esc(kk.inference_a)}</span>` : ''}</div>`;
    $('#sc').innerHTML = (it.game === 'gist' ? `<details class="card" style="margin-top:12px"><summary class="small" style="cursor:pointer">The passage again</summary><div class="passage" style="margin-top:8px;font-size:16px">${paras(it.passage)}</div></details>` : '') + keyHTML + `<p class="ask">Score your own answer the way a strict, fair editor would. These are the same anchors Claude uses.</p>
      ${Object.entries(rubric).map(([c, levels]) => `<div class="critrow"><b>${esc(c.replace('_', ' '))}</b><div class="rate5" data-c="${c}">${levels.map((_, n) => `<button class="opt" type="button" data-n="${n}">${n}</button>`).join('')}</div><span class="anch" data-a="${c}">Pick a score to see what it means.</span></div>`).join('')}
      <button class="btn" id="save" type="button" disabled>Save to the golden set</button>`;
    $('#sc').querySelectorAll('[data-c]').forEach(row => row.onclick = e => {
      const b = e.target.closest('button'); if (!b) return; const c = row.dataset.c; mine[c] = +b.dataset.n;
      [...row.children].forEach(x => x.classList.toggle('on', x === b));
      $(`[data-a="${c}"]`).textContent = `${b.dataset.n}: ${rubric[c][+b.dataset.n]}`;
      $('#save').disabled = Object.keys(mine).length < Object.keys(rubric).length;
    });
    $('#save').onclick = async () => {
      await api('/api/golden', { body: { item_id: it.id, answer, mine } });
      $('#sc').innerHTML = `<div class="verdict"><span class="band">Saved to the golden set</span><span class="small">Claude grades your answer blind in the background, and the agreement report updates.</span></div><button class="btn ghost" type="button" id="back">Back to the golden set</button>`;
      $('#back').onclick = () => go('golden');
    };
  };
}
