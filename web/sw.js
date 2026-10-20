// Binah's service worker: the app shell opens without a network. The API always goes to
// the network (answers, grades and ratings live on the server).
const CACHE = 'binah-shell-v2';
const SHELL = ['/', '/app.js', '/play.js', '/shell.js', '/style.css', '/manifest.webmanifest', '/icon.svg', '/icon-192.png',
  '/fonts/newsreader-latin-wght-normal.woff2', '/fonts/newsreader-latin-wght-italic.woff2', '/fonts/figtree-latin-wght-normal.woff2',
  '/fonts/frank-ruhl-libre-hebrew-wght-normal.woff2'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin || u.pathname.startsWith('/api/')) return;
  e.respondWith(fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); } return r; })
    .catch(() => caches.match(e.request).then(r => r || caches.match('/'))));
});
