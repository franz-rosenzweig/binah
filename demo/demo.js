// Technique or Fair Move?, played entirely in the browser from the snippets written for Binah
// (content/technique.json). Same rules as the app: half tricks, half the same move done fairly,
// an optional technique label for a bonus, and a confidence on every call.
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ORDER = ['emotional manipulation', 'false choice', 'scapegoating', 'fake or irrelevant expert', 'attack on the person', 'cherry-picking', 'slippery slope', 'conspiracy framing'];
const SEEN = 'binah-demo-seen';
const box = $('#round');
let all = [];

function seen() { try { return new Set(JSON.parse(localStorage.getItem(SEEN) || '[]')); } catch { return new Set(); } }
function remember(ids) { try { const s = seen(); ids.forEach(i => s.add(i)); localStorage.setItem(SEEN, JSON.stringify([...s].slice(-150))); } catch { /* private window */ } }
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

// Three tricks and three fair moves, each on a different technique where possible, unseen ones first.
function pickRound() {
  const s = seen();
  const fresh = all.filter(x => !s.has(x.id));
  const pool = fresh.length >= 24 ? fresh : all;
  const out = [], used = new Set();
  for (const kind of ['technique', 'fair']) {
    for (const it of shuffle(pool.filter(x => x.kind === kind))) {
      if (out.filter(x => x.kind === kind).length === 3) break;
      if (used.has(it.technique)) continue;
      used.add(it.technique); out.push(it);
    }
  }
  return shuffle(out);
}

function mark(text, tell) {
  const i = tell ? text.indexOf(tell) : -1;
  return i < 0 ? esc(text) : esc(text.slice(0, i)) + `<mark>${esc(tell)}</mark>` + esc(text.slice(i + tell.length));
}

function one(it, i, n, results) {
  return new Promise(resolve => {
    let kind = null, tech = null;
    box.innerHTML = `<div class="dots">${Array.from({ length: n }, (_, j) => `<i class="${j < results.length ? (results[j].kindOk ? 'ok' : 'no') : j === i ? 'now' : ''}"></i>`).join('')}</div>
      <p class="small muted" style="margin-bottom:6px">${esc(it.context)}</p><div class="tech-text" id="tt">${esc(it.text)}</div>
      <div class="btns" style="margin-top:10px"><button class="opt" type="button" data-k="technique">Manipulation</button><button class="opt" type="button" data-k="fair">Fair move</button></div>
      <div id="techPick" hidden><p class="ask">Which technique? (optional, a bonus if right)</p><div class="pills" id="tp">${ORDER.map(t => `<button class="opt" type="button" data-t="${esc(t)}">${esc(t)}</button>`).join('')}</div></div>
      <div class="conf"><span>How sure are you?</span><b id="cv">70%</b></div><input type="range" id="cr" min="50" max="100" step="5" value="70" aria-label="How sure are you?" style="width:100%">
      <button class="btn" id="send" type="button" disabled>Call it</button><div id="out"></div>`;
    const kinds = [...box.querySelectorAll('[data-k]')];
    kinds.forEach(b => b.onclick = () => { if (b.disabled) return; kind = b.dataset.k; kinds.forEach(x => x.classList.toggle('on', x === b)); $('#techPick').hidden = kind !== 'technique'; $('#send').disabled = false; });
    $('#tp').onclick = e => { const b = e.target.closest('button'); if (!b || b.disabled) return; tech = tech === b.dataset.t ? null : b.dataset.t; [...$('#tp').children].forEach(x => x.classList.toggle('on', x.dataset.t === tech)); };
    $('#cr').oninput = () => { $('#cv').textContent = $('#cr').value + '%'; };
    $('#send').onclick = () => {
      $('#send').remove(); kinds.forEach(x => x.disabled = true); [...$('#tp').children].forEach(x => x.disabled = true); $('#cr').disabled = true;
      const kindOk = kind === it.kind, labelOk = kindOk && it.kind === 'technique' && tech === it.technique;
      kinds.forEach(x => { if (x.dataset.k === it.kind) x.classList.add('key'); else if (x.dataset.k === kind) x.classList.add('miss'); });
      $('#tt').innerHTML = mark(it.text, it.tell);
      $('#out').innerHTML = `<div class="verdict"><span class="band">${kindOk ? 'Right' : 'Not quite'} · ${it.kind === 'fair' ? 'a fair move' : esc(it.technique)}</span>
          ${it.kind === 'fair' ? `<span class="small">It looks like ${esc(it.technique)}, but it's done fairly.</span>` : labelOk ? '<span class="small">And you named the technique.</span>' : ''}
          <span>${esc(it.why)}</span></div><button class="btn" type="button" id="nx">${i + 1 < n ? 'Next' : 'See how you did'}</button>`;
      $('#nx').onclick = () => resolve({ it, kind, tech, kindOk, labelOk, confidence: +$('#cr').value });
      $('#nx').focus({ preventScroll: true });
    };
  });
}

async function round() {
  const items = pickRound();
  const results = [];
  for (let i = 0; i < items.length; i++) results.push(await one(items[i], i, items.length, results));
  remember(items.map(x => x.id));
  const tricks = results.filter(r => r.it.kind === 'technique'), fair = results.filter(r => r.it.kind === 'fair');
  const caught = tricks.filter(r => r.kind === 'technique').length, flagged = fair.filter(r => r.kind === 'technique').length;
  const named = tricks.filter(r => r.labelOk).length;
  const right = results.filter(r => r.kindOk).length;
  const brier = results.reduce((a, r) => { const p = r.confidence / 100; return a + (r.kindOk ? (1 - p) ** 2 : p ** 2); }, 0) / results.length;
  box.innerHTML = `<div class="dots">${results.map(r => `<i class="${r.kindOk ? 'ok' : 'no'}"></i>`).join('')}</div>
    <p class="score">${right} of ${results.length} right</p>
    <p style="margin-top:8px">You caught <b>${caught} of ${tricks.length}</b> tricks and called <b>${flagged} of ${fair.length}</b> fair moves tricks${caught ? `, and you named ${named} of the techniques` : ''}.</p>
    <p class="small muted" style="margin-top:8px">${flagged > caught ? "You're leaning suspicious: more fair moves got flagged than tricks got caught." : caught === tricks.length && !flagged ? 'Clean round.' : ''} Your confidence scored ${brier.toFixed(2)} on the Brier scale, where 0 is perfect and 0.25 is a coin flip. In the app, these calls go into a discernment score that keeps your bias separate, so getting more suspicious never looks like getting sharper.</p>
    <button class="btn" type="button" id="again">Play another round</button>`;
  $('#again').onclick = round;
}

fetch('technique.json').then(r => r.json()).then(data => { all = data; round(); })
  .catch(() => { box.innerHTML = '<p class="small muted">The snippets didn’t load. Try reloading the page.</p>'; });
