/* Keep this version in sync with APP_VERSION in index.html.
   Bump by severity: PATCH 1.0.x (fix) · MINOR 1.x.0 (feature) · MAJOR x.0.0 (rework). */
const CACHE = "FitTrack-v1.2.1";
self.addEventListener("message", e => {
  if (e.data === "skip") self.skipWaiting();
  else if (e.data === "version" && e.ports[0]) e.ports[0].postMessage({ version: CACHE.replace("FitTrack-v", "") });
});
const SHELL = ["./", "./index.html", "./manifest.webmanifest", "./icon.svg"];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => Promise.allSettled(SHELL.map(u => c.add(u))))
  );
});
self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET" || !e.request.url.startsWith(self.location.origin)) return;
  const isPage = e.request.mode === "navigate" || e.request.destination === "document";
  if (isPage) {
    // NETWORK-FIRST for the app page: updates show up on the next load, cache only when offline
    e.respondWith(
      fetch(e.request).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
        return res;
      }).catch(() =>
        caches.match(e.request)
          .then(f => f || caches.match("./index.html"))
                )
    );
  } else {
    // cache-first for icons/manifest/etc.
    e.respondWith(
      caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {}); }
        return res;
      }))
    );
  }
});
