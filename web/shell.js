// The page's half of the Android app's contract (docs/SHELL.md). It does nothing in a
// plain browser: only when the user agent carries "Binah/<version> (Android shell)".
// (The Mac app is native now and doesn't load the page.)
const m = navigator.userAgent.match(/Binah\/([\d.]+) \((Android) shell\)/);
if (m) {
  const root = document.documentElement;
  root.classList.add('shell', 'shell-android');
  if (!window.binahShell) {
    // Android: calls go over a MessagePort the app posts to this page ("binah:port").
    let port = null, seq = 0;
    const waiting = new Map(), queue = [];
    const send = (op, args) => new Promise(resolve => {
      const id = ++seq;
      waiting.set(id, resolve);
      const msg = JSON.stringify({ id, op, args });
      port ? port.postMessage(msg) : queue.push(msg);
    });
    window.addEventListener('message', e => {
      if (e.data !== 'binah:port' || !e.ports || !e.ports[0]) return;
      port = e.ports[0];
      port.onmessage = ev => { try { const r = JSON.parse(ev.data); const f = waiting.get(r.id); if (f) { waiting.delete(r.id); f(r.result); } } catch { /* not ours */ } };
      queue.splice(0).forEach(q => port.postMessage(q));
      sendBars();
    });
    const ops = new Set(['haptic', 'bars', 'share', 'openExternal', 'mic']);
    window.binahShell = { platform: 'android', version: m[1], can: op => ops.has(op),
      haptic: kind => send('haptic', { kind }), bars: o => send('bars', o), share: o => send('share', o),
      openExternal: url => send('openExternal', { url }), mic: on => send('mic', { on: !!on }) };
  }
  const sendBars = () => {
    const css = getComputedStyle(root);
    const bg = css.getPropertyValue('--ground').trim();
    const dark = matchMedia('(prefers-color-scheme: dark)').matches;
    window.binahShell?.bars?.({ bg, dark });
  };
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', sendBars);
  window.addEventListener('load', sendBars);
}
