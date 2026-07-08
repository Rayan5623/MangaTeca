/* ============================================================
   Service Worker — Mangateca
   ------------------------------------------------------------
   • Cache dell'"app-shell" (HTML/manifest/icone) per far partire
     l'app anche offline.
   • Le chiamate DINAMICHE (Supabase, Jikan, libreria CDN) NON
     vengono mai servite dalla cache: vanno sempre in rete e, se
     offline, falliscono con grazia (l'app continua in locale).
   • Ad ogni release cambia CACHE_VERSION: i client scaricano la
     nuova build e la vecchia cache viene ripulita in "activate".
   ============================================================ */
const CACHE_VERSION = "mangateca-v3";

// File statici dell'app (same-origin). L'aggiunta è tollerante:
// se un'icona manca non blocca l'installazione.
const APP_SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icons/favicon-32.png",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/apple-touch-icon.png",
];

// Host che NON vanno mai messi in cache come app-shell: sempre rete.
const NETWORK_ONLY = [
  "supabase.co",     // API REST/Auth di Supabase
  "supabase.in",
  "api.jikan.moe",   // database titoli MyAnimeList/Jikan
  "cdn.jsdelivr.net" // libreria @supabase/supabase-js da CDN
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_VERSION);
    await Promise.all(APP_SHELL.map((url) => cache.add(url).catch(() => {})));
    self.skipWaiting(); // attiva subito la nuova versione
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // rimuove le cache delle versioni precedenti (es. mangateca-v2)
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const req = event.request;

  // Metodi non-GET (POST/PATCH/DELETE verso Supabase) → passthrough alla rete.
  if (req.method !== "GET") return;

  const url = new URL(req.url);

  // API dinamiche + libreria CDN → SEMPRE rete, mai cache; se offline, 503 pulito.
  if (NETWORK_ONLY.some((h) => url.hostname.includes(h))) {
    event.respondWith(
      fetch(req).catch(() => new Response("", { status: 503, statusText: "offline" }))
    );
    return;
  }

  // Solo le richieste same-origin (app-shell) passano dalla cache.
  if (url.origin !== self.location.origin) return;

  // Strategia stale-while-revalidate: risposta immediata dalla cache,
  // aggiornamento in background quando c'è rete.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_VERSION);
    const cached = await cache.match(req);
    const network = fetch(req)
      .then((res) => { if (res && res.ok) cache.put(req, res.clone()); return res; })
      .catch(() => null);
    return cached || (await network) || cache.match("./index.html");
  })());
});
