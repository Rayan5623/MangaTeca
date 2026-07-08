# CLAUDE.md — Mangateca

Contesto per sessioni future di Claude Code. Sintesi di architettura, modello
dati e strategia di sincronizzazione.

## Cos'è

Tracker di manga e fumetti, **mobile-first**, **PWA**. Tiene la collezione
volume per volume (posseduti / letti), con stato di lettura e note.

## Vincoli di stack (NON cambiare)

- **Un unico file `index.html`**: HTML + CSS + JavaScript **vanilla**.
- **Nessun framework, nessun build step** → resta impacchettabile come PWA/TWA.
- Dipendenze esterne solo via `<script>` da CDN. Oggi: `@supabase/supabase-js@2`.
- Palette scura: sfondo `#15110f`, accento `#e8552d`.

## File del progetto

| File | Ruolo |
|------|-------|
| `index.html` | Tutta l'app (UI + logica + sync). Era `mangateca.html`, rinominato in `index.html` per l'hosting statico. |
| `sw.js` | Service worker. Cache app-shell; Supabase/Jikan sempre in rete. Cache attuale: `mangateca-v3`. |
| `manifest.webmanifest` | Manifest PWA. |
| `icons/` | Icone PWA (da fornire: `icon-192.png`, `icon-512.png`, `favicon-32.png`, `apple-touch-icon.png`). |
| `supabase/schema.sql` | Tabella `series` + RLS. Da incollare nel SQL Editor di Supabase. |

## Configurazione

In cima a `index.html` due costanti da sostituire:

```js
const SUPABASE_URL      = "…";  // Project URL   (Supabase → Settings → API)
const SUPABASE_ANON_KEY = "…";  // anon public   (Supabase → Settings → API)
```

La anon key è **pubblica per design**: la sicurezza la fa la **Row Level
Security** (vedi `supabase/schema.sql`), non la segretezza della chiave.
Finché non vengono sostituite, l'app gira in **modalità solo-locale** senza errori.

## Modello dati (una serie)

```js
{
  id: "stringa-univoca",   // generato dal client (uid())
  type: "manga",           // "manga" | "comic" | "manhwa"
  title: "Berserk",
  author: "Kentaro Miura",
  total: 41,               // volumi totali (0 = sconosciuto)
  status: "reading",       // "reading" | "completed" | "planned" | "paused"
  cover: "https://…",      // url copertina, può essere ""
  notes: "…",
  owned: [1,2,3],          // numeri di volume posseduti
  read:  [1,2],            // numeri di volume letti
  ts: 1700000000000,       // timestamp creazione/ordinamento
  updated_at: 1700000000000, // ms, per il last-write-wins (aggiunto per la sync)
  pending: "queued"        // opzionale: "queued" | "confirm" | assente
}
```

La tabella DB `series` rispecchia questi campi (`owned`/`read` come JSONB,
`updated_at` come `timestamptz`, più `user_id uuid`).

## Le due code (non interferiscono)

1. **Coda Jikan** (già esistente): quando aggiungo una serie con dati mancanti
   viene salvata `pending:"queued"`; appena c'è rete si completa via
   `https://api.jikan.moe/v4/manga?q=…`. I match incerti diventano
   `pending:"confirm"` (badge "da confermare"). Funzioni: `runQueue`,
   `enrichOne`, `markConfirm`, `confirmSeries`.
2. **Coda Supabase** (sync): mirror remoto della collezione. Ogni volta che la
   coda Jikan modifica un record chiama `touch()`, quindi il record entra anche
   nella coda Supabase. Le due code lavorano in parallelo senza conflitti.

## Strategia di sincronizzazione (il cuore)

Offline-first, **last-write-wins**:

- **`localStorage` = fonte di verità** per la UI (istantanea, offline). Chiave
  `mangateca.v1`. L'oggetto in memoria è `DB` (array di serie).
- Ogni mutazione locale chiama **`touch(id)`** (o `markDeleted(id)`): aggiorna
  `updated_at` e mette l'id in una **coda persistente** (`mangateca.syncqueue.v1`,
  insiemi `upserts`/`deletes`).
- **Push** (`pushQueue`): quando c'è rete e sono loggato, la coda viene spinta su
  Supabase (`upsert` on conflict `id`, poi `delete`). Debounce 800ms.
- **Pull + merge** (`pullAndMerge`): all'avvio (e quando torna la rete) scarico le
  righe dell'utente e fondo con il locale. A parità di `id` vince `updated_at` più
  recente. Un record locale sparito dal server (e già sincronizzato in passato,
  vedi `mangateca.lastpull.v1`) è considerato **cancellato altrove** e rimosso.
- **`fullSync`** = push → pull/merge → push. Al **primo login** su un device
  (`mangateca.syncedonce.v1` assente) tutta la collezione locale viene caricata
  sull'account (merge lato server): niente dati persi.
- **Errori gestiti**: se Supabase non risponde, la coda resta su disco e si
  ritenta al prossimo evento `online`/avvio. L'app non si rompe mai.

Trigger della sync: `onAuthStateChange` (login/logout/avvio), evento `online`,
pulsante "Sincronizza ora" nello sheet Account.

Pallino di stato nell'header (`#syncDot`): grigio = locale/offline,
verde = sincronizzato, giallo = modifiche in coda, rosso = errore.

## Autenticazione

Magic link via email (Supabase Auth, `signInWithOtp`), **senza password**.
Sheet "Account e backup" (bottone nell'header). Senza login l'app funziona in
locale e mostra un avviso non invadente "Accedi per sincronizzare".
`emailRedirectTo` = URL corrente: **l'URL del sito va aggiunto ai Redirect URLs**
in Supabase Auth, altrimenti il link non torna all'app.

## Backup manuale

Nello sheet Account: **Esporta** (scarica `.json` con `{app,version,exportedAt,series}`)
e **Importa** (merge per `id`, con `updated_at` più recente che vince). Disponibile
anche senza login.

## Deploy

Hosting statico (Netlify/Vercel): è solo `index.html` + asset. Nessun server;
Supabase fa da backend. Dopo il deploy, aggiungere l'URL del sito ai Redirect
URLs di Supabase Auth.
