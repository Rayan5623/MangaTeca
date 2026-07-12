-- ============================================================
--  Mangateca — Schema database Supabase
-- ------------------------------------------------------------
--  DOVE INCOLLARLO:
--  Dashboard Supabase → menu a sinistra "SQL Editor" → "New query"
--  → incolla TUTTO questo file → premi "Run".
--  È idempotente: puoi rilanciarlo senza rompere nulla.
-- ============================================================

-- ------------------------------------------------------------
-- Tabella "series": rispecchia il modello dati del client.
-- ------------------------------------------------------------
--  • id            → chiave primaria testuale, generata dal client
--                    (uid() nel browser). Come richiesto, è il client
--                    a decidere l'id.
--                    NB: se un giorno volessi essere blindato contro
--                    collisioni di id tra utenti diversi, potresti usare
--                    una PK composta (user_id, id). Qui teniamo id come
--                    PK singola: semplice e sufficiente (uid casuale).
--  • user_id       → proprietario della riga, collegato a auth.users.
--                    ON DELETE CASCADE: se l'utente viene eliminato,
--                    spariscono anche le sue serie.
--  • owned / read  → array di numeri di volume, salvati come JSONB
--                    (comodo e 1:1 con gli array JS del client).
--  • pending       → stato della coda Jikan ("queued"/"confirm"/NULL).
--  • updated_at    → timestamp per la risoluzione dei conflitti
--                    (last-write-wins lato client).
create table if not exists public.series (
  id          text primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  type        text not null default 'manga',
  title       text not null default '',
  author      text default '',
  total       integer default 0,
  status      text default 'reading',
  cover       text default '',
  notes       text default '',
  owned       jsonb default '[]'::jsonb,
  read        jsonb default '[]'::jsonb,
  ts          bigint,
  pending     text,
  updated_at  timestamptz not null default now()
);

-- Indice per filtrare velocemente le righe dell'utente.
create index if not exists series_user_id_idx on public.series (user_id);

-- ------------------------------------------------------------
-- Row Level Security (RLS): il vero muro di sicurezza.
-- ------------------------------------------------------------
--  La anon key è pubblica (sta nel browser). Senza RLS chiunque
--  potrebbe leggere/scrivere tutto. Con RLS attiva + le policy sotto,
--  ogni utente autenticato vede e modifica SOLO le proprie righe
--  (quelle con user_id = auth.uid()).
alter table public.series enable row level security;

-- Le policy vanno (ri)create in modo idempotente: prima le elimino se esistono.
drop policy if exists "series_select_own" on public.series;
drop policy if exists "series_insert_own" on public.series;
drop policy if exists "series_update_own" on public.series;
drop policy if exists "series_delete_own" on public.series;

-- SELECT: leggo solo le mie righe.
create policy "series_select_own"
  on public.series for select
  using (auth.uid() = user_id);

-- INSERT: posso inserire solo righe intestate a me.
create policy "series_insert_own"
  on public.series for insert
  with check (auth.uid() = user_id);

-- UPDATE: posso modificare solo le mie righe, e devono restare mie.
create policy "series_update_own"
  on public.series for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- DELETE: posso eliminare solo le mie righe.
create policy "series_delete_own"
  on public.series for delete
  using (auth.uid() = user_id);
