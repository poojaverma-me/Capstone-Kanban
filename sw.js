// Service worker: makes the board installable and lets the app shell open offline.
// Board data always comes live from Supabase and is never cached here.
const VERSION = "board-v2"
const SHELL = [
  "./",
  "./index.html",
  "./agent.html",
  "./manifest.webmanifest?v=2",
  "./favicon.ico?v=2",
  "./icons/icon-192.png?v=2",
  "./icons/icon-512.png?v=2",
  "./icons/ios-180.png?v=2",
  "./icons/favicon-32.png?v=2",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.3/dist/umd/supabase.js",
]

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const req = event.request
  if (req.method !== "GET") return
  const url = new URL(req.url)
  // Supabase API, auth and realtime: always live.
  if (url.hostname.endsWith("supabase.co") || url.hostname.endsWith("supabase.in")) return

  // Pages: network first so updates show up straight away; cached copy when offline.
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone()
          caches.open(VERSION).then((c) => c.put(req, copy))
          return res
        })
        .catch(() => caches.match(req).then((hit) => hit || caches.match("./index.html")))
    )
    return
  }

  // Icons, manifest, the pinned Supabase library: cache first, refresh in the background.
  if (url.origin === self.location.origin || url.hostname === "cdn.jsdelivr.net") {
    event.respondWith(
      caches.match(req).then((hit) => {
        const fresh = fetch(req)
          .then((res) => {
            if (res.ok) {
              const copy = res.clone()
              caches.open(VERSION).then((c) => c.put(req, copy))
            }
            return res
          })
          .catch(() => hit)
        return hit || fresh
      })
    )
  }
})
