// FractalLab Service Worker — cache-first for app shell, network-first for updates
const CACHE = 'fractallab-v1';

const PRECACHE = [
  './',
  './index.html',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(PRECACHE))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Network-first for navigation; cache-first for assets
  const isNav = event.request.mode === 'navigate';
  event.respondWith(
    isNav
      ? fetch(event.request).catch(() => caches.match('./index.html'))
      : caches.match(event.request).then(
          (cached) => cached || fetch(event.request).then((res) => {
            if (res.ok) {
              const clone = res.clone();
              caches.open(CACHE).then((c) => c.put(event.request, clone));
            }
            return res;
          })
        )
  );
});
