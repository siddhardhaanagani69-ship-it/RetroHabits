import os
from datetime import datetime
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI
from google import genai
from pydantic import BaseModel

load_dotenv(Path(__file__).with_name(".env"))
DB = os.getenv("DATABASE_URL")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
# One shared client: a throwaway Client() gets garbage-collected mid-request.
gemini = genai.Client()

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
