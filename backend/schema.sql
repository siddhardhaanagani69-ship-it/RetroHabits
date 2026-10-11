-- Summarized agenda items (Canvas feed, iPhone calendar, Gmail/Teams mail).
create table if not exists items (
    id         text primary key,          -- same id the app uses for the AgendaItem
    source     text not null,             -- canvas | apple | gmail
    title      text not null,
    start_at   timestamptz,
    summary    text,                      -- Gemini's one-liner
    action     text,                      -- what you actually need to do
    urgency    smallint,                  -- 1 (low) .. 3 (high)
    course     text,                      -- short course code, if any
    done       boolean not null default false,
    updated_at timestamptz not null default now()
);

alter table items add column if not exists course text;  -- for DBs created before the column existed
-- Email deadlines and the body excerpt the chat answers from.
alter table items add column if not exists due timestamptz;
alter table items add column if not exists due_end timestamptz;
alter table items add column if not exists detail text;

-- Voice-note logs (workouts, study sessions, ...). Time-series, so a hypertable.
create table if not exists logs (
    ts       timestamptz not null default now(),
    kind     text not null,               -- workout | study | mood | note
    raw_text text,                        -- transcript
    data     jsonb not null default '{}'  -- structured fields from Gemini
);
select create_hypertable('logs', by_range('ts'), if_not_exists => true);
create index if not exists logs_kind_ts on logs (kind, ts desc);

-- Money. Recorded spending is time-series data: a hypertable, bucketed by week for trends.
create table if not exists spending (
    id       uuid not null default gen_random_uuid(),
    ts       timestamptz not null,             -- when the money was spent
    amount   numeric(10, 2) not null check (amount >= 0),
    category text not null,
    merchant text,
    note     text,
    source   text not null                     -- text | receipt
);
select create_hypertable('spending', by_range('ts'), if_not_exists => true);
create index if not exists spending_id on spending (id);

-- Small settings the server needs too (the weekly budget). One user, so plain key/value.
create table if not exists prefs (
    key   text primary key,
    value jsonb not null
);
