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

-- Voice-note logs (workouts, study sessions, ...). Time-series, so a hypertable.
create table if not exists logs (
    ts       timestamptz not null default now(),
    kind     text not null,               -- workout | study | mood | note
    raw_text text,                        -- transcript
    data     jsonb not null default '{}'  -- structured fields from Gemini
);
select create_hypertable('logs', by_range('ts'), if_not_exists => true);
create index if not exists logs_kind_ts on logs (kind, ts desc);
