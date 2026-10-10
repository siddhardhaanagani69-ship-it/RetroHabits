import json
import logging
import os
from datetime import datetime, time, timedelta
from pathlib import Path
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import psycopg
from backboard import BackboardClient, BackboardError
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, UploadFile
from google import genai
from google.genai import types
from psycopg.types.json import Jsonb
from pydantic import BaseModel

load_dotenv(Path(__file__).with_name(".env"))
DB = os.getenv("DATABASE_URL")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
# One shared client: a throwaway Client() gets garbage-collected mid-request.
gemini = genai.Client()
backboard = BackboardClient(api_key=os.getenv("BACKBOARD_API_KEY", ""))
log = logging.getLogger("uvicorn.error")

app = FastAPI(title="RetroHabits assistant")


@app.get("/health")
def health():
    if not DB:
        return {"ok": True, "db": "not configured"}
    try:
        with psycopg.connect(DB, connect_timeout=5) as conn:
            conn.execute("select 1")
        return {"ok": True, "db": "up"}
    except psycopg.Error as e:
        return {"ok": False, "db": str(e).splitlines()[0]}


# MARK: - Glance summaries

class Item(BaseModel):
    """An agenda item as the app sends it."""
    id: str
    source: str
    title: str
    start: datetime | None = None
    notes: str | None = None
    location: str | None = None


class Summary(BaseModel):
    id: str
    summary: str        # what it actually is, one glanceable line
    action: str         # the concrete thing to do ("" if nothing)
    urgency: int        # 1 low .. 3 high
    course: str | None  # e.g. "CHEM 1331"


PROMPT = """You turn noisy calendar, Canvas and Teams items into glanceable cards for a busy student.
For every item return, keeping its exact id:
- summary: what it actually is, max 12 words. Drop course codes, section numbers, URLs and boilerplate.
- action: the concrete thing to do, max 10 words, imperative ("Submit lab report"). Empty string if nothing to do.
- urgency: 3 if due or happening within 24 hours, 2 within 3 days, else 1.
- course: short course name like "CHEM 1331" if you can tell, else null.

Current time: {now}

Items (JSON):
{items}"""


@app.post("/summarize")
def summarize(items: list[Item]) -> list[Summary]:
    """Summaries for the given items. Anything already summarized with the same
    title comes from Tiger; only new or renamed items go to Gemini."""
    if not items:
        return []
    with psycopg.connect(DB) as conn:
        rows = conn.execute(
            "select id, title, summary, action, urgency, course from items where id = any(%s)",
            ([i.id for i in items],),
        ).fetchall()
        titles = {i.id: i.title for i in items}
        cached = {
            r[0]: Summary(id=r[0], summary=r[2], action=r[3], urgency=r[4], course=r[5])
            for r in rows
            if r[1] == titles[r[0]] and r[2] is not None
        }
        todo = [i for i in items if i.id not in cached]
        if todo:
            for s in _ask_gemini(todo):
                cached[s.id] = s
            by_id = {i.id: i for i in todo}
            conn.cursor().executemany(
                """insert into items (id, source, title, start_at, summary, action, urgency, course)
                   values (%s, %s, %s, %s, %s, %s, %s, %s)
                   on conflict (id) do update set
                     title = excluded.title, start_at = excluded.start_at, summary = excluded.summary,
                     action = excluded.action, urgency = excluded.urgency, course = excluded.course,
                     updated_at = now()""",
                [
                    (s.id, by_id[s.id].source, by_id[s.id].title, by_id[s.id].start,
                     s.summary, s.action, s.urgency, s.course)
                    for s in cached.values() if s.id in by_id
                ],
            )
    return [cached[i.id] for i in items if i.id in cached]


def _ask_gemini(items: list[Item]) -> list[Summary]:
    # Notes can be long Canvas/Teams boilerplate; the first part carries the meaning.
    payload = [i.model_copy(update={"notes": (i.notes or "")[:600] or None}) for i in items]
    resp = gemini.models.generate_content(
        model=GEMINI_MODEL,
        contents=PROMPT.format(
            now=datetime.now().astimezone().isoformat(timespec="minutes"),
            items="[" + ",".join(p.model_dump_json(exclude_none=True) for p in payload) + "]",
        ),
        config={"response_mime_type": "application/json", "response_schema": list[Summary]},
    )
    wanted = {i.id for i in items}
    return [s for s in (resp.parsed or []) if s.id in wanted]  # Gemini can drop or invent ids


# MARK: - Voice log

class Exercise(BaseModel):
    name: str
    sets: int | None = None
    reps: int | None = None
    weight: float | None = None
    unit: str | None = None       # lb | kg
    minutes: float | None = None  # cardio / timed work


class ParsedLog(BaseModel):
    kind: Literal["workout", "study", "mood", "note"]
    title: str                    # 2-5 words, e.g. "Leg day"
    transcript: str
    exercises: list[Exercise]
    mood: str | None
    memory: str                   # one factual sentence for long-term memory


LOG_PROMPT = """This is a quick voice note from a student logging their day. Transcribe it, then extract:
- kind: workout, study, mood or note
- title: 2-5 words ("Leg day", "DB project work")
- exercises: every exercise mentioned, with sets, reps, weight, unit and minutes when said. Empty list if not a workout.
- mood: one or two words if they say how they feel, else null
- memory: one factual sentence worth remembering long-term, naming the weekday,
  e.g. "On Tuesday did leg day: squats 3x8 at 135 lb, felt strong."
Today is {today}."""

ASSISTANT_PROMPT = (
    "You are a personal assistant for a university student. You remember their workouts, "
    "study sessions, plans and feelings, and give short, practical advice grounded in that history."
)
MAX_AUDIO_BYTES = 10 * 1024 * 1024  # ~5 min of 16 kHz WAV
_assistant_id: str | None = None


async def assistant_id() -> str:
    """The one Backboard assistant that holds this user's memory (created on first use)."""
    global _assistant_id
    if _assistant_id is None:
        found = await backboard.list_assistants(name="RetroHabits")
        a = found[0] if found else await backboard.create_assistant(
            name="RetroHabits", system_prompt=ASSISTANT_PROMPT)
        _assistant_id = str(a.assistant_id)
    return _assistant_id


@app.post("/log")
async def log_voice_note(audio: UploadFile) -> ParsedLog:
    data = await audio.read()
    if not data or len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(413, "Audio missing or longer than ~5 minutes")

    resp = await gemini.aio.models.generate_content(
        model=GEMINI_MODEL,
        contents=[
            types.Part.from_bytes(data=data, mime_type=audio.content_type or "audio/wav"),
            LOG_PROMPT.format(today=datetime.now().astimezone().strftime("%A %B %d %Y, %H:%M")),
        ],
        config={"response_mime_type": "application/json", "response_schema": ParsedLog},
    )
    parsed: ParsedLog | None = resp.parsed
    if parsed is None:
        raise HTTPException(502, "Couldn't understand the note")

    # Tiger is the source of truth; Backboard memory is best-effort on top.
    with psycopg.connect(DB) as conn:
        conn.execute(
            "insert into logs (kind, raw_text, data) values (%s, %s, %s)",
            (parsed.kind, parsed.transcript, Jsonb(parsed.model_dump(exclude={"kind", "transcript"}))),
        )
    try:
        await backboard.add_memory(await assistant_id(), content=parsed.memory,
                                   metadata={"kind": parsed.kind, "title": parsed.title})
    except BackboardError as e:
        log.warning("Backboard memory write failed: %s", e)
    return parsed


# MARK: - Weekly recall

class Recall(BaseModel):
    day: str | None            # "Saturday, Oct 3" — the session being recalled
    logs: list[dict]           # what was logged that day (title, exercises, mood, ...)
    suggestion: str | None     # Gemini's take on what to do today


RECALL_PROMPT = """The student is about to repeat their {weekday} routine. Last time ({day}) they logged:
{logs}

Things you remember about them that may matter (injuries, goals, feelings):
{memories}

In at most 2 short sentences, suggest what to do today: repeat, progress (be specific, e.g. +5 lb or +1 rep),
or ease off if a memory says so. Talk to them directly, no preamble."""


@app.get("/recall")
async def recall(tz: str = "UTC") -> Recall:
    """The most recent session on today's weekday in the last 4 weeks, plus a suggestion."""
    try:
        zone = ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError):
        raise HTTPException(400, f"Unknown time zone: {tz}")
    today = datetime.now(zone).date()
    since = datetime.combine(today - timedelta(days=28), time.min, zone)
    until = datetime.combine(today, time.min, zone)

    # A time-bounded scan on the hypertable only touches the last few chunks.
    with psycopg.connect(DB) as conn:
        rows = conn.execute(
            """select ts, kind, raw_text, data from logs
               where ts >= %s and ts < %s and extract(isodow from ts at time zone %s) = %s
               order by ts""",
            (since, until, tz, today.isoweekday()),
        ).fetchall()
    if not rows:
        return Recall(day=None, logs=[], suggestion=None)

    last_date = rows[-1][0].astimezone(zone).date()
    logs = [{"kind": kind, "transcript": text, **data}
            for ts, kind, text, data in rows if ts.astimezone(zone).date() == last_date]
    for entry in logs:
        entry.pop("memory", None)  # already phrased for Backboard; noise here

    memories = "none"
    try:
        found = await backboard.search_memories(
            await assistant_id(), query=" ".join(l["title"] for l in logs), limit=5)
        memories = "\n".join(f"- {m['content']}" for m in found.get("memories", [])) or "none"
    except BackboardError as e:
        log.warning("Backboard memory search failed: %s", e)

    day = last_date.strftime("%A, %b %-d")
    resp = await gemini.aio.models.generate_content(
        model=GEMINI_MODEL,
        contents=RECALL_PROMPT.format(weekday=today.strftime("%A"), day=day,
                                      logs=json.dumps(logs), memories=memories),
    )
    return Recall(day=day, logs=logs, suggestion=(resp.text or "").strip() or None)
