// The monthly benchmark: one sitting on a sealed form, about thirty-five minutes. No feedback until
// the end, every answer is saved as it's given (so a sitting can stop and pick up later), and the
// results live on their own track, apart from practice ratings.
import { $, api, esc, toast, haptic, state, go, bar, isM3 } from './app.js';

const main = document.getElementById('main');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const paras = t => String(t || '').split(/\n\s*\n/).map(p => `<p>${esc(p)}</p>`).join('');
const SEC = { argument: 'Arguments', discern: 'Fair or trick', inference: 'Reading', essay: 'The essay', talk: 'The talk', vocab: 'Words' };
const LET = 'ABCDE';
const pct = r => r && r.of ? `${Math.round(100 * r.right / r.of)}%` : '—';
const day = iso => iso ? new Date(iso.replace(' ', 'T') + (iso.includes('+') || iso.endsWith('Z') ? '' : 'Z')).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : '';
const essayAvg = g => g && !g.failed && g.structure != null ? ((g.structure + g.accuracy + g.understanding) / 3).toFixed(1) : null;
const talkAvg = g => g && !g.failed && g.deviation != null ? ((g.hesitation + g.repetition + g.deviation + g.structure) / 4).toFixed(1) : null;
let keyHandler = null;
function onKeys(f) { if (keyHandler) document.removeEventListener('keydown', keyHandler); keyHandler = f; if (f) document.addEventListener('keydown', f); }

export async function bench(rest = []) {
  onKeys(null);
  try {
    if (rest[0] === 'run') return await sitting();
    if (rest[0] === 'review' && rest[1]) return await review(+rest[1]);
    return await overview();
  } catch (e) { if (e.message !== 'signed out') main.innerHTML = head('Benchmark') + `<p class="err">${esc(e.message)}</p>`; bindX(); }
}

function head(name, prog = '', sub = 'Monthly benchmark') {
  return bar({ title: name, sub, back: true, kind: 'game', actions: prog ? `<span class="capsule">${esc(prog)}</span>` : '' });
}
// After each render: what follows the header goes into the screen's body; back goes to `to`.
function bindX(to = 'skills') {
  const hd = main.querySelector(':scope > .bar');
  if (hd && !main.querySelector(':scope > .body')) {
    const body = document.createElement('div');
    body.className = 'body game';
    while (hd.nextSibling) body.appendChild(hd.nextSibling);
    main.appendChild(body);
  }
  const f = () => { onKeys(null); go(to); };
  const x = $('#barBack'); if (x) x.onclick = f;
  state.back = f;
}

// ── the overview: when the next sitting is due, and every sitting so far ──

async function overview() {
  const { forms, runs } = await api('/api/benchmark');
  const open = runs.find(r => !r.finished);
  const done = runs.filter(r => r.finished);
  const used = new Set(runs.map(r => r.form));
  const unused = forms.filter(f => !used.has(f.id)).length;
  const last = done[done.length - 1];
  const due = last ? new Date(new Date(last.finished).getTime() + 28 * 864e5) : null;
  const early = due && due > new Date();
  const rows = done.map(r => { const x = r.results || {};
    return `<tr data-run="${r.id}" style="cursor:pointer"><td style="white-space:nowrap">${esc(new Date(r.finished).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }))}</td><td class="n">${pct(x.argument)}</td><td class="n">${pct(x.inference)}</td><td class="n">${pct(x.vocab)}</td><td class="n">${x.discern ? x.discern.dprime : '—'}</td><td class="n">${x.brier ?? '—'}</td><td class="n">${essayAvg((x.essay || {}).grade) ?? '…'}</td><td class="n">${talkAvg((x.talk || {}).grade) ?? '…'}</td></tr>`; }).join('');
  main.innerHTML = bar({ title: 'Benchmark', sub: isM3() ? '' : 'A sealed test, once a month', back: isM3(), kind: isM3() ? 'game' : 'big' }) + `
    <p class="lede">Once a month, a sealed test you never practise on: eight arguments, eight fair-or-trick calls, two passages with three questions each, a 15-minute essay, a 2-minute talk and six words. About 35 minutes. Answers save as you go, so you can stop and come back. You see what you missed at the end.</p>
    <div class="card" style="margin-top:14px">
      ${open ? `<p><b>You have a sitting in progress.</b></p><button class="btn" id="go" type="button">Continue it</button>`
        : unused ? `<p>${last ? (early ? `Next one is due around <b>${due.toLocaleDateString(undefined, { day: 'numeric', month: 'long' })}</b>. A month between sittings keeps the comparison fair.` : '<b>A sitting is due.</b>') : '<b>Take the first one to set your baseline.</b>'}</p>
           <p class="small">${unused} sealed form${unused === 1 ? '' : 's'} ready.</p><button class="btn ${early ? 'ghost' : ''}" id="go" type="button">${early ? 'Start one anyway' : 'Start a sitting'}</button>`
        : `<p class="muted">${forms.length ? 'Every sealed form has been used.' : 'No sealed forms yet.'} New ones are written on the server with <code>python -m binah.benchgen</code>.</p>`}
    </div>
    ${done.length ? `<div class="sec"><span class="label">Sittings</span></div><div class="card" style="overflow-x:auto"><table class="tbl"><thead><tr><th>Date</th><th>Arg.</th><th>Read</th><th>Words</th><th>d′</th><th>Brier</th><th>Essay</th><th>Talk</th></tr></thead><tbody>${rows}</tbody></table>
      <p class="small" style="margin-top:8px">Essay and talk are out of 4. Brier: 0 is perfect calibration, 0.25 a coin flip. With eight items a section, one sitting is noisy; trust a change only once it holds for two sittings.</p></div>` : ''}`;
  bindX();
  const g = $('#go'); if (g) g.onclick = () => { haptic('tick'); go('bench/run'); };
  main.querySelectorAll('[data-run]').forEach(r => r.onclick = () => go('bench/review/' + r.dataset.run));
}

// ── a sitting ──

function stepsOf(form) {
  const out = [];
  for (const s of form.sections) {
    if (s.kind === 'argument' || s.kind === 'vocab' || s.kind === 'discern') s.items.forEach(it => out.push({ sec: s.kind, key: `${s.kind}:${it.id}`, it }));
    else if (s.kind === 'inference') s.passages.forEach((p, pi) => p.questions.forEach(q => out.push({ sec: 'inference', key: `inference:${q.id}`, it: q, passage: p, pi })));
    else out.push({ sec: s.kind, key: s.kind, it: s });
  }
  return out;
}
const answered = (st, ans) => st.sec === 'essay' ? !!(ans.essay && ans.essay.done) : st.sec === 'talk' ? !!ans.talk : ans[st.key] != null;

async function sitting() {
  const r = await api('/api/benchmark/start', { body: {} });
  const steps = stepsOf(r.form), ans = r.answers || {};
  const passages = (r.form.sections.find(s => s.kind === 'inference') || {}).passages || [];
  const save = (key, value) => { ans[key] = value; return api(`/api/benchmark/${r.run}/answer`, { body: { key, value } }); };
  let i = steps.findIndex(st => !answered(st, ans));
  const next = () => { i = steps.findIndex(st => !answered(st, ans)); window.scrollTo(0, 0); show(); };
  function show() {
    if (i < 0) return finishScreen();
    const st = steps[i], prog = `${i + 1} of ${steps.length}`;
    if (st.sec === 'essay') return essay(st.it, prog);
    if (st.sec === 'talk') return talk(st.it, prog);
    return choice(st, prog);
  }

  function choice(st, prog) {
    const it = st.it, binary = st.sec === 'discern';
    const opts = binary ? [['technique', 'Manipulation'], ['fair', 'Fair move']] : it.options.map((o, k) => [k, o]);
    const floor = binary ? 50 : st.sec === 'argument' ? 20 : 25;
    let pick = null;
    const body = st.sec === 'argument' ? `<div class="passage" style="font-size:17px">${paras(it.stimulus)}</div><p class="ask" style="color:var(--ink)"><b>${esc(it.stem)}</b></p>`
      : st.sec === 'vocab' ? `<div class="tech-text">${esc(it.sentence).replace(new RegExp(`\\b(${it.word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})\\b`, 'i'), '<mark>$1</mark>')}</div><p class="ask" style="color:var(--ink)"><b>What does “${esc(it.word)}” mean here?</b></p>`
      : st.sec === 'inference' ? `<details class="card" ${st.it.id === st.passage.questions[0].id ? 'open' : ''}><summary class="small" style="cursor:pointer">Passage ${st.pi + 1}${st.passage.source ? ' · ' + esc(st.passage.source) : ''}</summary><div class="passage" style="margin-top:10px">${paras(st.passage.text)}</div></details><p class="ask" style="color:var(--ink)"><b>${esc(it.stem)}</b></p>`
      : `<p class="small" style="margin-bottom:6px">${esc(it.context)}</p><div class="tech-text">${esc(it.text)}</div><p class="ask">Manipulative as written, or a fair move?</p>`;
    main.innerHTML = head(SEC[st.sec], prog) + body + `<div class="${binary ? 'tk' : 'opts'}" id="op" style="${binary ? '' : 'display:grid;gap:8px'}">${opts.map(([v, t], k) => `<button class="opt" type="button" data-v="${v}" ${binary ? 'style="text-align:center"' : ''}>${binary ? '' : `<b style="margin-right:8px">${LET[k]}</b>`}${esc(t)}</button>`).join('')}</div>
      <div class="conf"><span>How sure are you?</span><b id="cv">${Math.max(floor, 70)}%</b></div><input type="range" id="cr" min="${floor}" max="100" step="5" value="${Math.max(floor, 70)}" aria-label="Confidence">
      <button class="btn" id="nx" type="button" disabled>${i + 1 < steps.length ? 'Next' : 'Done'}</button>`;
    bindX('bench');
    const btns = [...main.querySelectorAll('[data-v]')];
    const choose = b => { pick = binary ? b.dataset.v : +b.dataset.v; btns.forEach(x => x.classList.toggle('on', x === b)); $('#nx').disabled = false; haptic('tick'); };
    btns.forEach(b => b.onclick = () => choose(b));
    $('#cr').oninput = () => { $('#cv').textContent = $('#cr').value + '%'; };
    $('#nx').onclick = async () => {
      $('#nx').disabled = true;
      try { await save(st.key, binary ? { kind: pick, confidence: +$('#cr').value } : { choice: pick, confidence: +$('#cr').value }); next(); }
      catch (e) { toast(e.message); $('#nx').disabled = false; }
    };
    onKeys(e => {
      if (e.target.closest('input,textarea')) return;
      const n = '12345'.indexOf(e.key), l = LET.indexOf(e.key.toUpperCase());
      const k = n >= 0 ? n : l;
      if (k >= 0 && btns[k]) choose(btns[k]);
      else if (e.key === 'Enter' && !$('#nx').disabled) $('#nx').click();
    });
  }

  function essay(sec, prog) {
    onKeys(null);
    const draft = ans.essay || {};
    const started = draft.started || Date.now();
    const total = (sec.minutes || 15) * 60;
    const ref = passages[1] || passages[0];
    main.innerHTML = head(SEC.essay, prog) + `<p class="ask" style="color:var(--ink);margin-top:6px"><b>${esc(sec.prompt)}</b></p>
      ${ref ? `<details class="card"><summary class="small" style="cursor:pointer">The passage${ref.source ? ' · ' + esc(ref.source) : ''}</summary><div class="passage" style="margin-top:10px">${paras(ref.text)}</div></details>` : ''}
      <div class="conf"><span id="wc">0 words</span><b id="tm"></b></div>
      <textarea class="ta" id="es" style="min-height:300px;margin-top:6px" aria-label="Your essay">${esc(draft.text || '')}</textarea>
      <button class="btn" id="dn" type="button">I'm done</button><p class="small">It saves as you type. Fifteen minutes is the limit, and the reasoning counts more than the length.</p>`;
    bindX('bench');
    const ta = $('#es');
    let last = ta.value, timer = null, closed = false;
    const wc = () => { $('#wc').textContent = `${(ta.value.trim().match(/\S+/g) || []).length} words`; };
    const persist = async done => { last = ta.value; await save('essay', { text: ta.value, started, done: !!done }); };
    const close = async why => {
      if (closed) return; closed = true;
      clearInterval(timer); ta.readOnly = true;
      if (why) toast(why);
      try { await persist(true); next(); } catch (e) { closed = false; toast(e.message); }
    };
    const tick = () => {
      const left = Math.max(0, total - (Date.now() - started) / 1000);
      $('#tm').textContent = `${Math.floor(left / 60)}:${String(Math.floor(left % 60)).padStart(2, '0')}`;
      if (left <= 0) close("Time's up. Your essay is saved.");
      else if (ta.value !== last && Math.floor(left) % 15 === 0) persist(false).catch(() => {});
    };
    if (!draft.started) persist(false).catch(() => {});
    wc(); tick(); timer = setInterval(tick, 1000);
    ta.oninput = wc; ta.onblur = () => { if (ta.value !== last && !closed) persist(false).catch(() => {}); };
    $('#dn').onclick = () => close();
    state.back = () => { clearInterval(timer); if (!closed) persist(false).catch(() => {}); go('bench'); };
    $('#barBack').onclick = state.back;
    ta.focus();
  }

  function talk(sec, prog) {
    onKeys(null);
    const secs = sec.seconds || 120;
    let rec = null, chunks = [], t0 = 0, timer = null, stream = null;
    main.innerHTML = head(SEC.talk, prog) + `<p class="small" style="text-align:center;margin-top:6px">Two minutes, spoken. Make one point and support it.</p>
      <p class="topic" style="margin-top:18px">${esc(sec.prompt)}</p>
      <div class="rec"><div class="ring"><svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="44" style="fill:none;stroke:var(--sunk);stroke-width:7"/><circle id="arc" cx="50" cy="50" r="44" style="fill:none;stroke:var(--accent);stroke-width:7;stroke-linecap:round;stroke-dasharray:276.5;stroke-dashoffset:276.5"/></svg><span class="t" id="tm">${secs}</span></div>
        <button class="recbtn" id="rb" type="button" aria-label="Start recording"><i></i></button><span class="small" id="rs">Tap to start. It stops by itself at two minutes.</span></div>
      <div id="out"></div><button class="btn link" id="skip" type="button">Skip the talk this time</button>`;
    const stopAll = () => { if (timer) clearInterval(timer); timer = null; if (stream) stream.getTracks().forEach(t => t.stop()); };
    bindX('bench');
    state.back = () => { stopAll(); if (rec && rec.state === 'recording') { rec.onstop = null; rec.stop(); window.binahShell?.mic?.(false); } go('bench'); };
    $('#barBack').onclick = state.back;
    $('#skip').onclick = async () => { stopAll(); try { await save('talk', { skipped: true }); next(); } catch (e) { toast(e.message); } };
    const finish = () => { if (rec && rec.state === 'recording') rec.stop(); };
    $('#rb').onclick = async () => {
      if (rec && rec.state === 'recording') return finish();
      try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } }); }
      catch { toast("Binah can't use the microphone. Allow it in the browser or app settings, or skip the talk."); return; }
      const mime = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'].find(m => window.MediaRecorder && MediaRecorder.isTypeSupported(m)) || '';
      rec = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      chunks = [];
      rec.ondataavailable = e => { if (e.data.size) chunks.push(e.data); };
      rec.onstop = async () => {
        stopAll(); window.binahShell?.mic?.(false);
        $('#rb').classList.remove('on'); $('#rb').disabled = true; $('#rs').textContent = 'Uploading…'; $('#skip').hidden = true;
        const fd = new FormData();
        fd.append('file', new Blob(chunks, { type: rec.mimeType || 'audio/webm' }), 'talk.' + ((rec.mimeType || '').includes('mp4') ? 'mp4' : 'webm'));
        try { await api(`/api/benchmark/${r.run}/talk`, { body: fd }); ans.talk = { audio: true }; next(); }
        catch (e) { $('#rs').textContent = e.message; $('#rb').disabled = false; $('#skip').hidden = false; }
      };
      rec.start(1000); t0 = Date.now();
      window.binahShell?.mic?.(true);
      $('#rb').classList.add('on'); $('#rb').setAttribute('aria-label', 'Stop'); $('#rs').textContent = 'Tap to stop early.'; haptic('confirm');
      timer = setInterval(() => {
        const left = Math.max(0, secs - (Date.now() - t0) / 1000);
        $('#tm').textContent = Math.ceil(left);
        $('#arc').style.strokeDashoffset = String(276.5 * (left / secs));
        if (left <= 0) finish();
      }, 200);
    };
  }

  function finishScreen() {
    onKeys(null);
    main.innerHTML = head("That's everything") + `
      <p class="lede" style="margin-top:12px">Hand it in to see your scores and what you missed. The essay and the talk are graded on the server and arrive a minute or two later.</p>
      <button class="btn" id="fin" type="button">Hand it in</button>`;
    bindX('bench');
    $('#fin').onclick = async () => {
      $('#fin').disabled = true;
      try { await api(`/api/benchmark/${r.run}/finish`, { body: {} }); haptic('confirm'); go('bench/review/' + r.run); }
      catch (e) { toast(e.message); $('#fin').disabled = false; }
    };
  }

  show();
}

// ── a finished sitting: the scores, then every miss with its explanation ──

async function review(run) {
  let d = await api(`/api/benchmark/${run}`);
  const draw = () => {
    const x = d.results || {}, a = d.answers || {};
    const eg = (x.essay || {}).grade, tg = (x.talk || {}).grade;
    const wroteEssay = !!(a.essay && (a.essay.text || '').trim()), talked = !!(a.talk && !a.talk.skipped);
    const misses = [];
    for (const s of d.form.sections) {
      if (s.kind === 'argument' || s.kind === 'vocab') s.items.forEach(it => { const m = a[`${s.kind}:${it.id}`] || {}; if (m.choice !== it.answer) misses.push({ s: s.kind, it, m }); });
      else if (s.kind === 'inference') s.passages.forEach(p => p.questions.forEach(q => { const m = a[`inference:${q.id}`] || {}; if (m.choice !== q.answer) misses.push({ s: 'inference', it: q, m, p }); }));
      else if (s.kind === 'discern') s.items.forEach(it => { const m = a[`discern:${it.id}`] || {}; if (m.kind !== it.kind) misses.push({ s: 'discern', it, m }); });
    }
    const opt = (it, k) => k == null ? 'no answer' : `${LET[k]}. ${esc(it.options[k])}`;
    const missHtml = misses.map(({ s, it, m }) => s === 'discern'
      ? `<div class="card" style="margin-bottom:8px"><span class="label">${SEC[s]}</span><div class="tech-text" style="margin-top:6px;font-size:16px">${esc(it.text)}</div><p class="small" style="margin-top:6px">You said <b>${m.kind === 'technique' ? 'manipulation' : m.kind === 'fair' ? 'fair' : 'nothing'}</b>${m.confidence ? ` (${m.confidence}% sure)` : ''}. It's <b>${it.kind === 'fair' ? 'a fair move' : esc(it.technique)}</b>${it.kind === 'fair' ? `, resembling ${esc(it.technique)}` : ''}.</p>${it.tell ? `<p class="small">The tell: <q>${esc(it.tell)}</q></p>` : ''}<p class="small">${esc(it.why || '')}</p></div>`
      : `<div class="card" style="margin-bottom:8px"><span class="label">${SEC[s]}</span>${s === 'vocab' ? `<p style="margin-top:6px">${esc(it.sentence)}</p>` : s === 'argument' ? `<details style="margin-top:6px"><summary class="small" style="cursor:pointer">The argument</summary><div class="passage" style="font-size:16px;margin-top:6px">${paras(it.stimulus)}</div></details>` : ''}
          <p style="margin-top:6px"><b>${esc(s === 'vocab' ? `“${it.word}”` : it.stem)}</b></p><p class="small" style="color:var(--bad)">You: ${opt(it, m.choice)}${m.confidence ? ` (${m.confidence}% sure)` : ''}</p><p class="small" style="color:var(--ok)">Answer: ${opt(it, it.answer)}</p>${it.explanation ? `<p class="small">${esc(it.explanation)}</p>` : ''}</div>`).join('');
    const dd = x.discern || {};
    main.innerHTML = head('Your sitting', '', `Monthly benchmark · ${day(d.finished)}`) + `
      <div class="counts" style="margin-top:12px"><div><b>${pct(x.argument)}</b><span>arguments${x.argument ? ` · ${x.argument.right}/${x.argument.of}` : ''}</span></div><div><b>${pct(x.inference)}</b><span>reading${x.inference ? ` · ${x.inference.right}/${x.inference.of}` : ''}</span></div><div><b>${pct(x.vocab)}</b><span>words${x.vocab ? ` · ${x.vocab.right}/${x.vocab.of}` : ''}</span></div>
        <div><b>${dd.dprime ?? '—'}</b><span>discernment d′</span></div><div><b>${x.brier ?? '—'}</b><span>calibration (Brier)</span></div><div><b>${essayAvg(eg) ?? (wroteEssay ? '…' : '—')}</b><span>essay, out of 4</span></div></div>
      ${dd.of_tricks ? `<p class="small" style="margin-top:8px">Fair or trick: caught ${dd.hits} of ${dd.of_tricks} tricks, called ${dd.false_alarms} of ${dd.of_fair} fair moves tricks. Bias ${dd.bias > 0.15 ? 'toward calling things fair' : dd.bias < -0.15 ? 'toward calling things tricks' : 'balanced'} (${dd.bias}).</p>` : ''}
      <div class="sec"><span class="label">The essay</span></div>
      <div class="card">${!wroteEssay ? '<p class="muted">Not written this time.</p>' : eg && eg.failed ? '<p class="muted">Grading failed twice. It is logged on the server.</p>' : eg ? `<p class="small">structure ${eg.structure}/4 · accuracy ${eg.accuracy}/4 · understanding ${eg.understanding}/4${eg.spread >= 2 ? ' · the two readings disagreed, so take this one loosely' : ''}</p>${eg.strength ? `<p class="plus"><b>+</b> ${esc(eg.strength)}</p>` : ''}${eg.work_on ? `<p class="minus"><b>→</b> ${esc(eg.work_on)}</p>` : ''}` : '<div class="wait"><i></i><span>Being graded, twice, and averaged…</span></div>'}
        ${wroteEssay ? `<details style="margin-top:8px"><summary class="small" style="cursor:pointer">What you wrote</summary><p class="transcript" style="margin-top:6px;white-space:pre-wrap">${esc(a.essay.text)}</p></details>` : ''}</div>
      <div class="sec"><span class="label">The talk</span></div>
      <div class="card">${!talked ? '<p class="muted">Skipped this time.</p>' : tg && tg.failed ? '<p class="muted">Grading failed twice. It is logged on the server.</p>' : tg ? `<div class="metrics"><div><b>${Math.round((tg.metrics || {}).speaking_time || 0)}s</b><span>speaking</span></div><div><b>${Math.round((tg.metrics || {}).wpm || 0)}</b><span>words a minute</span></div><div><b>${((tg.metrics || {}).fillers_per_min ?? 0).toFixed(1)}</b><span>fillers a minute</span></div></div>
          <p class="small">hesitation ${tg.hesitation}/4 · repetition ${tg.repetition}/4 · deviation ${tg.deviation}/4 · structure ${tg.structure}/4</p>${tg.strength ? `<p class="plus"><b>+</b> ${esc(tg.strength)}</p>` : ''}${tg.work_on ? `<p class="minus"><b>→</b> ${esc(tg.work_on)}</p>` : ''}
          <details style="margin-top:8px"><summary class="small" style="cursor:pointer">What you said</summary><p class="transcript" style="margin-top:6px">${esc(tg.text || '')}</p></details>` : '<div class="wait"><i></i><span>Transcribing, then grading…</span></div>'}</div>
      <div class="sec"><span class="label">${misses.length ? `What you missed (${misses.length})` : 'What you missed'}</span></div>
      ${missHtml || '<p class="muted">Nothing. Every multiple-choice answer was right.</p>'}
      <button class="btn ghost" id="bk" type="button">All sittings</button>`;
    bindX('bench');
    $('#bk').onclick = () => go('bench');
    return (wroteEssay && !eg) || (talked && !tg);
  };
  let pending = draw();
  for (let n = 0; pending && n < 80 && state.route === 'bench' && location.hash === `#bench/review/${run}`; n++) {
    await sleep(n < 10 ? 4000 : 8000);
    if (location.hash !== `#bench/review/${run}`) break;
    const y = window.scrollY;
    d = await api(`/api/benchmark/${run}`);
    pending = draw();
    window.scrollTo(0, y);
  }
}
