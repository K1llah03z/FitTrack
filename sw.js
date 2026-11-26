/* FitTrack service worker.
   VERSION (year.month.DDNN) must match APP_VERSION in index.html. publish.ps1 updates both automatically. */
const VERSION = "2026.11.2607";
const CACHE = "FitTrack-v" + VERSION;
const COOKBOOK = "https://k1llah03z.github.io/CookBook/recipes.js";
const SHELL = ["./", "./index.html", "./manifest.webmanifest", "./icon.svg"];
const PAGE_TIMEOUT = 3000; // weak gym signal: fall back to the saved copy after 3 s

self.addEventListener("message", e => {
  if (e.data === "skip") self.skipWaiting();
  else if (e.data === "version" && e.ports[0]) e.ports[0].postMessage({ version: VERSION });
});

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c =>
    Promise.allSettled(SHELL.map(u => c.add(new Request(u, { cache: "reload" }))))));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== CACHE && k !== "FitTrack-cookbook").map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

function networkFirst(req, cacheName, timeoutMs) {
  return new Promise(resolve => {
    let done = false;
    const fromCache = () => caches.match(req, { ignoreSearch: true })
      .then(hit => hit || caches.match("./index.html"));
    const timer = timeoutMs ? setTimeout(() => {
      fromCache().then(hit => { if (hit && !done) { done = true; resolve(hit); } });
    }, timeoutMs) : null;
    fetch(req).then(res => {
      if (res && (res.ok || res.type === "opaque")) {
        const copy = res.clone();
        caches.open(cacheName).then(c => c.put(req, copy)).catch(() => {});
      }
      clearTimeout(timer);
      if (!done) { done = true; resolve(res); }
    }).catch(() => {
      clearTimeout(timer);
      fromCache().then(hit => { if (!done) { done = true; resolve(hit || Response.error()); } });
    });
  });
}

self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const url = e.request.url;
  // cookbook recipes (other repo): fresh when online, saved copy offline
  if (url.split("?")[0] === COOKBOOK) {
    e.respondWith(fetch(e.request).then(res => {
      const copy = res.clone(); caches.open("FitTrack-cookbook").then(c => c.put(COOKBOOK, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match(COOKBOOK).then(h => h || Response.error())));
    return;
  }
  if (!url.startsWith(self.location.origin)) return;
  const isPage = e.request.mode === "navigate" || e.request.destination === "document";
  if (isPage) { e.respondWith(networkFirst(e.request, CACHE, PAGE_TIMEOUT)); return; }
  // cache-first for icons/manifest/etc.
  e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {}); }
    return res;
  })));
});

// lock-screen alerts from the server (fasting "1 hour to go" / "Fast complete", test alert)
self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { title: "FitTrack", body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "FitTrack", {
    body: d.body || "", tag: d.tag || "fittrack", icon: "icon.svg", badge: "icon.svg",
    data: { url: d.url || "./" }, renotify: true, requireInteraction: false
  }));
});

// tapping a reminder opens (or focuses) the app
self.addEventListener("notificationclick", e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(list => {
    for (const c of list) if ("focus" in c) return c.focus();
    return self.clients.openWindow("./");
  }));
});
