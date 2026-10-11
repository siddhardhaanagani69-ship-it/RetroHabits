import asyncio
import base64
import email
import json
import logging
import os
import re
import secrets
import urllib.error
import urllib.request
from datetime import datetime, time, timedelta
from email import policy
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
import psycopg
from backboard import BackboardClient, BackboardError
from dotenv import load_dotenv
import requests
from fastapi import Depends, FastAPI, Form, HTTPException, Request, Response, UploadFile
from fastapi.responses import JSONResponse
from google import genai
from google.genai import errors as genai_errors
from google.auth.exceptions import RefreshError
from google.auth.transport.requests import AuthorizedSession
from google.oauth2.credentials import Credentials
from google.genai import types
from psycopg.types.json import Jsonb
from pydantic import BaseModel

import ripple as rp

load_dotenv(Path(__file__).with_name(".env"))
DB = os.getenv("DATABASE_URL")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
# One shared client: a throwaway Client() gets garbage-collected mid-request.
# No hidden SDK retries (they can sleep for minutes on a 429) and a 25 s timeout:
# a model that fails or stalls hands over to the next one in GEMINI_MODELS instead.
gemini = genai.Client(http_options=types.HttpOptions(
    timeout=25_000, retry_options=types.HttpRetryOptions(attempts=1)))
# The free tier caps requests per model per day (20 for gemini-3.8-flash), and each
# model has its own quota, so when one runs out (429) or is retired (404) the next takes over.
GEMINI_MODELS = [GEMINI_MODEL] + [
    m for m in os.getenv("GEMINI_FALLBACKS",
              "gemini-3.7-flash,gemini-3.6-flash,gemini-3.5-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite").split(",")
    if m and m != GEMINI_MODEL
]


def _try_next(e: Exception) -> bool:
    """Retired model (404), out of quota (429), overloaded (5xx) or stalled: try the next model."""
    return isinstance(e, httpx.TimeoutException) or getattr(e, "code", None) in (404, 429, 500, 503, 504)


def _why(e: Exception) -> str:
    return "timeout" if isinstance(e, httpx.TimeoutException) else str(e.code)


async def generate(contents, config=None):
    for i, model in enumerate(GEMINI_MODELS):
        try:
            return await gemini.aio.models.generate_content(model=model, contents=contents, config=config)
        except (genai_errors.APIError, httpx.TimeoutException) as e:
            if not _try_next(e) or i == len(GEMINI_MODELS) - 1:
                raise
            log.warning("Gemini %s unavailable (%s); falling back to %s", model, _why(e), GEMINI_MODELS[i + 1])


def generate_sync(contents, config=None):
    for i, model in enumerate(GEMINI_MODELS):
        try:
            return gemini.models.generate_content(model=model, contents=contents, config=config)
        except (genai_errors.APIError, httpx.TimeoutException) as e:
            if not _try_next(e) or i == len(GEMINI_MODELS) - 1:
                raise
            log.warning("Gemini %s unavailable (%s); falling back to %s", model, _why(e), GEMINI_MODELS[i + 1])
backboard = BackboardClient(api_key=os.getenv("BACKBOARD_API_KEY", ""))
log = logging.getLogger("uvicorn.error")

API_TOKEN = os.getenv("API_TOKEN")


def require_token(request: Request) -> None:
    """Everything but /health needs `Authorization: Bearer <API_TOKEN>` once a token
    is set. The data behind this API is personal (agenda, email, memories) and every
    call spends model credits, so a public server must not be open."""
    if not API_TOKEN or request.url.path == "/health":
        return
    sent = request.headers.get("authorization", "").removeprefix("Bearer ")
    if not secrets.compare_digest(sent.encode(), API_TOKEN.encode()):
        raise HTTPException(401, "Missing or wrong API token")


app = FastAPI(title="RetroHabits assistant", dependencies=[Depends(require_token)])


@app.exception_handler(genai_errors.APIError)
async def gemini_failed(request: Request, e: genai_errors.APIError) -> JSONResponse:
    """Say what went wrong instead of a bare 500."""
    if e.code == 429:
        return JSONResponse({"detail": "Gemini's free daily quota is used up on every model. "
                                       "Try again later or turn on billing for the Gemini API key."}, 503)
    return JSONResponse({"detail": f"Gemini error {e.code}: {e.message}"}, 502)


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
    due: datetime | None = None      # emails only: a deadline or event time the email states
    due_end: datetime | None = None  # emails only: when that event ends, if stated


PROMPT = """You turn noisy calendar, Canvas and Teams items into glanceable cards for a busy student.
For every item return, keeping its exact id:
- summary: what it actually is, max 12 words. Drop course codes, section numbers, URLs and boilerplate.
- action: the concrete thing to do, max 10 words, imperative ("Submit lab report"). Empty string if nothing to do.
- urgency: 3 if something must be done or attended within 24 hours, 2 within 3 days, else 1.
  Pure FYI with nothing to do is always 1.
- course: short course name like "CHEM 1331" if you can tell, else null.
- due / due_end: ONLY for items with source "gmail". If the email states a deadline or a scheduled
  time ("due Monday 11:59 PM", "meeting Tuesday 2-3pm"), give it as ISO 8601 with UTC offset, reading
  relative days from the email's own date ("start"). due_end only for an event with an end time.
  Null when no date is stated, and always null for non-email items. Never guess a date.

Current time: {now}

Items (JSON):
{items}"""


@app.post("/summarize")
def summarize(items: list[Item], tz: str = "UTC") -> list[Summary]:
    """Summaries for the given items. Anything already summarized with the same
    title comes from Tiger; only new or renamed items go to Gemini."""
    if not items:
        return []
    with psycopg.connect(DB) as conn:
        rows = conn.execute(
            "select id, title, summary, action, urgency, course, due, due_end from items where id = any(%s)",
            ([i.id for i in items],),
        ).fetchall()
        titles = {i.id: i.title for i in items}
        cached = {
            r[0]: Summary(id=r[0], summary=r[2], action=r[3], urgency=r[4], course=r[5], due=r[6], due_end=r[7])
            for r in rows
            if r[1] == titles[r[0]] and r[2] is not None
        }
        todo = [i for i in items if i.id not in cached]
        if todo:
            for s in _ask_gemini(todo, _zone(tz)):
                cached[s.id] = s
            by_id = {i.id: i for i in todo}
            conn.cursor().executemany(
                """insert into items (id, source, title, start_at, summary, action, urgency, course, due, due_end, detail)
                   values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                   on conflict (id) do update set
                     title = excluded.title, start_at = excluded.start_at, summary = excluded.summary,
                     action = excluded.action, urgency = excluded.urgency, course = excluded.course,
                     due = excluded.due, due_end = excluded.due_end, detail = excluded.detail,
                     updated_at = now()""",
                [
                    (s.id, by_id[s.id].source, by_id[s.id].title, by_id[s.id].start,
                     s.summary, s.action, s.urgency, s.course, s.due, s.due_end,
                     # email body kept so the chat can answer questions about it
                     (by_id[s.id].notes or "")[:1500] if by_id[s.id].source == "gmail" else None)
                    for s in cached.values() if s.id in by_id
                ],
            )
    return [cached[i.id] for i in items if i.id in cached]


def _ask_gemini(items: list[Item], zone: ZoneInfo) -> list[Summary]:
    # Notes can be long Canvas/Teams boilerplate; the first part carries the meaning.
    payload = [i.model_copy(update={"notes": (i.notes or "")[:600] or None}) for i in items]
    resp = generate_sync(
        contents=PROMPT.format(
            now=datetime.now(zone).isoformat(timespec="minutes"),
            items="[" + ",".join(p.model_dump_json(exclude_none=True) for p in payload) + "]",
        ),
        config={"response_mime_type": "application/json", "response_schema": list[Summary]},
    )
    wanted = {i.id: i for i in items}
    out = [s for s in (resp.parsed or []) if s.id in wanted]  # Gemini can drop or invent ids
    for s in out:
        if wanted[s.id].source != "gmail":
            s.due = s.due_end = None   # deadlines come from the calendar itself, not the model
    return out


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

    resp = await generate(
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


# MARK: - Memory retrieval (shared, inspectable)

class MemoryRef(BaseModel):
    """A memory that was handed to the model, so the app can show why it said something."""
    id: str
    content: str
    score: float | None = None
    weak: bool = False         # loose retrieval match: shown to the user as uncertain


WEAK_MATCH = 0.35  # Backboard relevance below this is a loose match


async def search_memories(query: str, limit: int) -> list[MemoryRef]:
    try:
        found = await backboard.search_memories(await assistant_id(), query=query, limit=limit)
    except BackboardError as e:
        log.warning("Backboard memory search failed: %s", e)
        return []
    return [MemoryRef(id=m["id"], content=m["content"], score=m.get("score"),
                      weak=(m.get("score") or 0) < WEAK_MATCH) for m in found.get("memories", [])]


def bullets(memories: list[MemoryRef]) -> str:
    return "\n".join(f"- {m.content}" for m in memories) or "none"


# MARK: - Weekly recall

class Recall(BaseModel):
    day: str | None            # "Saturday, Oct 3" — the session being recalled
    logs: list[dict]           # what was logged that day (title, exercises, mood, ...)
    suggestion: str | None     # Gemini's take on what to do today
    memories_used: list[MemoryRef] = []


RECALL_PROMPT = """The student is about to repeat their {weekday} routine. Last time ({day}) they logged:
{logs}

Things you remember about them that may matter (injuries, goals, feelings):
{memories}

In at most 2 short sentences, suggest what to do today: repeat, progress (be specific, e.g. +5 lb or +1 rep),
or ease off if a memory says so. Talk to them directly, no preamble."""


@app.get("/recall")
async def recall(tz: str = "UTC") -> Recall:
    """The most recent session on today's weekday in the last 4 weeks, plus a suggestion."""
    zone = _zone(tz)
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

    memories = await search_memories(" ".join(l["title"] for l in logs), limit=5)
    day = last_date.strftime("%A, %b %-d")
    resp = await generate(
        contents=RECALL_PROMPT.format(weekday=today.strftime("%A"), day=day,
                                      logs=json.dumps(logs), memories=bullets(memories)),
    )
    return Recall(day=day, logs=logs, suggestion=(resp.text or "").strip() or None, memories_used=memories)


# MARK: - Chat

class Turn(BaseModel):
    role: Literal["user", "assistant"]
    text: str


class ChatIn(BaseModel):
    message: str
    history: list[Turn] = []   # the conversation so far, kept by the app
    tz: str = "UTC"


class ChatOut(BaseModel):
    reply: str
    memories_used: list[MemoryRef] = []


def _zone(tz: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError):
        raise HTTPException(400, f"Unknown time zone: {tz}")


def _context(zone: ZoneInfo) -> str:
    """What's coming up, what was logged lately and recent email, as plain text for the model."""
    now = datetime.now(zone)
    window = (now - timedelta(hours=2), now + timedelta(days=4))
    with psycopg.connect(DB) as conn:
        # Calendar/Canvas items by their time; emails only if they state a deadline in the window.
        items = conn.execute(
            """select coalesce(due, start_at) as at, coalesce(summary, title), action, source from items
               where not done and (
                 (source <> 'gmail' and start_at >= %s and start_at < %s) or
                 (source = 'gmail' and due >= %s and due < %s))
               order by at limit 30""",
            (*window, *window),
        ).fetchall()
        logs = conn.execute(
            "select ts, kind, data->>'title', raw_text from logs where ts >= %s order by ts",
            (now - timedelta(days=7),),
        ).fetchall()
        mails = conn.execute(
            """select start_at, title, summary, action, due, detail from items
               where source = 'gmail' and start_at >= %s order by start_at desc limit 15""",
            (now - timedelta(days=3),),
        ).fetchall()
    agenda = "\n".join(
        f"- {at.astimezone(zone):%a %b %d %H:%M}: {summary}" + (f" (to do: {action})" if action else "")
        + (" [from email]" if source == "gmail" else "")
        for at, summary, action, source in items) or "- nothing scheduled"
    recent = "\n".join(
        f"- {ts.astimezone(zone):%a %b %d}: {kind} '{title}': {text}" for ts, kind, title, text in logs
    ) or "- nothing logged"
    inbox = "\n".join(
        f"- {received.astimezone(zone):%a %b %d %H:%M} | {subject} | {summary}"
        + (f" | to do: {action}" if action else "") + (f" | due {due.astimezone(zone):%a %b %d %H:%M}" if due else "")
        + (f"\n  excerpt: {detail[:500]}" if detail else "")
        for received, subject, summary, action, due, detail in mails) or "- no recent email"
    return (f"[Background from the app, not written by the user. Now: {now:%A %B %d %Y, %H:%M}]\n"
            f"Upcoming:\n{agenda}\n\nLogged in the last 7 days:\n{recent}\n\n"
            f"Recent email (last 3 days, newest first):\n{inbox}\n\n"
            f"Money:\n{_money_context(zone)}")


_memory_thread: str | None = None


async def remember(text: str) -> None:
    """Let Backboard pull lasting facts out of what the user said. Backboard's free
    tier covers memory but not LLM chat, so the message is stored, not answered."""
    global _memory_thread
    try:
        if _memory_thread is None:
            _memory_thread = str((await backboard.create_thread(await assistant_id())).thread_id)
        await backboard.add_message(_memory_thread, content=text, memory="Auto", send_to_llm="false")
    except BackboardError as e:
        log.warning("Backboard memory write failed: %s", e)


@app.post("/chat")
async def chat(body: ChatIn) -> ChatOut:
    if not body.message.strip() or len(body.message) > 4000:
        raise HTTPException(400, "Message must be 1-4000 characters")
    zone = _zone(body.tz)

    memories = await search_memories(body.message, limit=8)

    system = (f"{ASSISTANT_PROMPT} Keep answers short and conversational; this is a phone chat.\n\n"
              f"{_context(zone)}\n\nWhat you remember about them:\n{bullets(memories)}")
    turns = body.history[-20:] + [Turn(role="user", text=body.message)]
    resp = await generate(
        contents=[types.Content(role="user" if t.role == "user" else "model", parts=[types.Part(text=t.text)])
                  for t in turns],
        config={"system_instruction": system},
    )
    reply = (resp.text or "").strip()
    if not reply:
        raise HTTPException(502, "The assistant didn't answer")
    await remember(body.message)
    return ChatOut(reply=reply, memories_used=memories)


# MARK: - Gmail (incl. Teams notification emails)

class MailBrief(Summary):
    sender: str
    received: datetime
    subject: str
    excerpt: str          # start of the body, for the detail view
    link: str | None      # opens the message in Gmail


# Gmail search syntax: recent inbox mail, minus promos/social noise.
GMAIL_QUERY = "in:inbox newer_than:2d -category:promotions -category:social"
MAX_MAILS = 25
# Read-only: this server can never send, delete or change mail.
GMAIL_SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]
GMAIL_TOKEN = Path(__file__).with_name("gmail_token.json")  # written by gmail_auth.py
GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me/messages"
_gmail: AuthorizedSession | None = None


def _gmail_session() -> AuthorizedSession:
    """Session that refreshes its own access token from the saved refresh token."""
    global _gmail
    if _gmail is None:
        if not GMAIL_TOKEN.exists():
            raise HTTPException(503, "Gmail isn't connected (run gmail_auth.py)")
        _gmail = AuthorizedSession(Credentials.from_authorized_user_file(str(GMAIL_TOKEN), GMAIL_SCOPES))
    return _gmail


def _parse_mail(raw: bytes) -> tuple[Item, str]:
    """(agenda-style item, sender)"""
    msg = email.message_from_bytes(raw, policy=policy.default)
    part = msg.get_body(preferencelist=("plain", "html"))
    body = part.get_content() if part else ""
    if part is not None and part.get_content_type() == "text/html":
        body = re.sub(r"<(style|script)[^>]*>.*?</\1>|<[^>]+>", " ", body, flags=re.S | re.I)
    body = re.sub(r"\s+", " ", body).strip()
    try:
        received = parsedate_to_datetime(msg["Date"])
    except (TypeError, ValueError):
        received = None
    sender = str(msg["From"] or "")
    return Item(
        id="gmail-" + (msg["Message-ID"] or f"{msg['Subject']}|{msg['Date']}").strip("<> "),
        source="gmail",
        title=str(msg["Subject"] or "(no subject)"),
        start=received,
        notes=f"From: {sender}\n{body[:1500]}",
    ), sender


@app.get("/mail")
def mail(tz: str = "UTC") -> list[MailBrief]:
    """Recent important email, summarized like agenda items (read-only Gmail API)."""
    session = _gmail_session()
    try:
        found = session.get(GMAIL_API, params={"q": GMAIL_QUERY, "maxResults": MAX_MAILS}, timeout=20)
        found.raise_for_status()
        raws = []   # (gmail message id, raw RFC 822 bytes)
        for ref in found.json().get("messages", []):
            msg = session.get(f"{GMAIL_API}/{ref['id']}", params={"format": "raw"}, timeout=20)
            msg.raise_for_status()
            raws.append((ref["id"], base64.urlsafe_b64decode(msg.json()["raw"])))
        account = _gmail_address(session)
    except RefreshError:
        raise HTTPException(502, "Gmail sign-in expired or was revoked — run gmail_auth.py again")
    except requests.RequestException as e:
        raise HTTPException(502, f"Gmail fetch failed: {e}")

    parsed = [(gid, *_parse_mail(raw)) for gid, raw in raws]
    by_id = {item.id: (gid, item, sender) for gid, item, sender in parsed}
    out = []
    for s in summarize([item for _, item, _ in parsed], tz):
        gid, item, sender = by_id[s.id]
        out.append(MailBrief(
            **s.model_dump(), sender=sender, subject=item.title,
            received=item.start or datetime.now().astimezone(),
            excerpt=(item.notes or "").split("\n", 1)[-1][:700],
            # authuser picks the right account when several are signed in to Gmail.
            link=f"https://mail.google.com/mail/?authuser={account}#all/{gid}" if account else None,
        ))
    return out


_gmail_account: str | None = None


def _gmail_address(session: AuthorizedSession) -> str | None:
    global _gmail_account
    if _gmail_account is None:
        r = session.get("https://gmail.googleapis.com/gmail/v1/users/me/profile", timeout=20)
        _gmail_account = r.json().get("emailAddress") if r.ok else None
    return _gmail_account


# MARK: - Spoken briefing (ElevenLabs)

BRIEFING_PROMPT = """Write a spoken daily briefing for this student, to be read aloud by a voice assistant.
Under 90 words. Warm, upbeat, direct. Cover what matters today and tomorrow, the most urgent to-do first,
and one line on their training from the logs if there is any. No markdown, lists, emojis or URLs.

{context}"""
ELEVENLABS_MODEL = os.getenv("ELEVENLABS_MODEL", "eleven_multilingual_v2")
_voice_id: str | None = os.getenv("ELEVENLABS_VOICE_ID") or None


def _elevenlabs(path: str, body: dict | None = None) -> bytes:
    req = urllib.request.Request(
        f"https://api.elevenlabs.io{path}",
        data=json.dumps(body).encode() if body else None,
        headers={"xi-api-key": os.getenv("ELEVENLABS_API_KEY", ""), "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def _speak(text: str) -> bytes:
    global _voice_id
    if _voice_id is None:  # no voice configured: use the account's first voice
        _voice_id = json.loads(_elevenlabs("/v1/voices"))["voices"][0]["voice_id"]
    return _elevenlabs(f"/v1/text-to-speech/{_voice_id}?output_format=mp3_44100_128",
                       {"text": text, "model_id": ELEVENLABS_MODEL})


async def briefing_text(zone: ZoneInfo) -> str:
    resp = await generate(
        contents=BRIEFING_PROMPT.format(context=_context(zone)))
    return (resp.text or "").strip()


async def _mp3(text: str) -> Response:
    if not os.getenv("ELEVENLABS_API_KEY", "").startswith("sk_"):
        raise HTTPException(503, "ElevenLabs isn't set up (ELEVENLABS_API_KEY should start with sk_)")
    try:
        audio = await asyncio.to_thread(_speak, text)
    except urllib.error.HTTPError as e:
        raise HTTPException(502, f"ElevenLabs error {e.code}: {e.read()[:200].decode(errors='replace')}")
    return Response(audio, media_type="audio/mpeg")


@app.get("/briefing")
async def briefing(tz: str = "UTC") -> Response:
    """Today's agenda and training, as an MP3 read by ElevenLabs."""
    text = await briefing_text(_zone(tz))
    if not text:
        raise HTTPException(502, "Couldn't write the briefing")
    return await _mp3(text)


class SpeakIn(BaseModel):
    text: str


@app.post("/speak")
async def speak(body: SpeakIn) -> Response:
    """Read a chat reply aloud in the same voice as the briefing."""
    # Markdown marks would be read out literally ("asterisk asterisk").
    text = re.sub(r"[*_#`>]+", "", body.text).strip()
    if not text or len(text) > 2500:
        raise HTTPException(400, "Text must be 1-2500 characters")
    return await _mp3(text)



# MARK: - Ripple Mode

class AgendaIn(BaseModel):
    id: str
    title: str
    start: datetime
    end: datetime | None = None   # no end = a deadline, which doesn't occupy time
    all_day: bool = False


class PlanIn(BaseModel):
    """A habit with a planned time, as the app holds it."""
    id: str
    name: str
    weekdays: list[int]           # 1 = Sunday ... 7 = Saturday
    hour: int
    minute: int
    duration: int = 60
    moves: dict[str, datetime] = {}


class RippleIn(BaseModel):
    change: str
    agenda: list[AgendaIn]
    plans: list[PlanIn]
    tz: str = "UTC"


class ParsedChange(BaseModel):
    kind: Literal["move", "new", "cancel"]
    target_id: str | None
    title: str
    start: datetime | None
    end: datetime | None
    hypothetical: bool
    stated: list[str]
    assumptions: list[str]
    cost: float | None = None     # money the change involves, only when an amount is stated


RIPPLE_PROMPT = """The student describes a change to their schedule, or asks "what if". Match it to their agenda.
Return:
- kind: "move" (an existing item changes time), "new" (something added), "cancel" (an existing item is dropped)
- target_id: the id of the agenda item it refers to, or null if it's new or you can't tell
- title: short name of the commitment
- start / end: ISO 8601 with UTC offset, time zone {tz}. Null if they gave no day or time at all.
- hypothetical: true for "what if…" or "thinking about…", false for something that actually changed
- stated: the facts they actually said, as short phrases
- assumptions: everything you filled in that they did NOT say, e.g. "Assumed 'evening' means 6 PM",
  "Assumed this Friday, not next". Empty list if nothing was assumed.
- cost: the amount of money this involves if they state one ("$45 ticket", "costs 20 bucks"), as a number. Null otherwise; never guess a price.
Never invent reasons, feelings or consequences.

Now: {now}
Agenda for the next 7 days:
{agenda}

What they said: {change}"""


def _block(a: AgendaIn) -> rp.Block | None:
    if a.all_day or a.end is None or a.end <= a.start:
        return None
    return rp.Block(a.id, a.title, a.start, a.end, "calendar")


def _span(delta: timedelta) -> str:
    h, m = divmod(int(delta.total_seconds()) // 60, 60)
    return f"{h}h{m:02d}" if m else f"{h} hour{'s' if h != 1 else ''}"


@app.post("/ripple")
async def ripple_mode(body: RippleIn) -> dict:
    """What one change collides with, and where displaced plans could go.
    Nothing is applied: the app shows this as a hypothetical until the user accepts."""
    if not body.change.strip() or len(body.change) > 1000:
        raise HTTPException(400, "Describe the change in 1-1000 characters")
    zone = _zone(body.tz)
    now = datetime.now(zone)
    agenda = {a.id: a for a in body.agenda}

    listing = "\n".join(
        f"- id={a.id} | {a.title} | {a.start.astimezone(zone):%a %b %d %H:%M}"
        + (f"-{a.end.astimezone(zone):%H:%M}" if a.end else " (deadline)") for a in body.agenda
    ) or "- (empty)"
    resp = await generate(
        contents=RIPPLE_PROMPT.format(tz=body.tz, now=f"{now:%A %B %d %Y %H:%M}", agenda=listing,
                                      change=body.change),
        config={"response_mime_type": "application/json", "response_schema": ParsedChange},
    )
    p: ParsedChange | None = resp.parsed
    if p is None:
        raise HTTPException(502, "Couldn't understand the change")

    target = agenda.get(p.target_id) if p.target_id else None
    assumptions = list(p.assumptions)
    clarify = None
    change = None
    if p.kind == "cancel" and target is None:
        clarify = "Which commitment is cancelled? I couldn't match it to your agenda."
    elif p.kind != "cancel":
        if p.start is None:
            clarify = f"When is “{p.title}”? Add a day and time."
        else:
            start = p.start if p.start.tzinfo else p.start.replace(tzinfo=zone)
            end = p.end if p.end and p.end.tzinfo else (p.end.replace(tzinfo=zone) if p.end else None)
            if end is None or end <= start:
                if target and target.end and target.end > target.start:
                    length = target.end - target.start
                    assumptions.append(f"Assumed it still lasts {_span(length)}, like before")
                else:
                    length = timedelta(hours=1)
                    assumptions.append("Assumed it lasts 1 hour (no end time given)")
                end = start + length
            change = rp.Block("change", p.title, start, end, "change")

    replaced = target.id if target and p.kind in ("move", "cancel") else None
    plans = [rp.Plan(x.id, x.name, set(x.weekdays), x.hour, x.minute, x.duration, dict(x.moves))
             for x in body.plans]
    calendar = [b for b in map(_block, body.agenda) if b]
    conflicts = rp.ripple(change, replaced, calendar, plans, now, zone) if not clarify else []
    return {
        "hypothetical": p.hypothetical,
        "clarify": clarify,
        "change": {
            "kind": p.kind, "title": p.title,
            "start": change.start if change else None, "end": change.end if change else None,
            "previous_start": target.start if target else None,
            "previous_end": target.end if target else None,
            "stated": p.stated, "assumptions": assumptions,
        },
        "conflicts": conflicts,
        "money": _planned_cost(zone, p.cost, change.start if change else now),
    }


def _planned_cost(zone: ZoneInfo, cost: float | None, at: datetime) -> dict | None:
    """What a stated cost would leave of that week's budget. It stays a plan: nothing
    is recorded as spent until the user logs it."""
    if cost is None or cost < 0:
        return None
    m = _money(zone, at)
    return {"cost": round(cost, 2), "budget": m["budget"], "remaining": m["remaining"],
            "after": round(m["remaining"] - cost, 2) if m["remaining"] is not None else None,
            "week_start": m["week_start"]}


# MARK: - Campus Capture

class FlyerEvent(BaseModel):
    is_event: bool
    title: str
    start: datetime | None
    end: datetime | None
    location: str | None
    cost: str | None            # exactly as printed ("Free", "$5"), null if the flyer doesn't say
    cost_amount: float | None = None   # that price as a number; 0 when free; null when not printed
    organizer: str | None
    summary: str                # one plain line
    topics: list[str]           # 1-4 subject words
    missing: list[str]          # useful details the flyer doesn't give
    assumptions: list[str]      # anything filled in, e.g. the year


class InterestMatch(BaseModel):
    memory_id: str
    why: str


class InterestCheck(BaseModel):
    matches: list[InterestMatch]


class CaptureContext(BaseModel):
    agenda: list[AgendaIn] = []
    plans: list[PlanIn] = []
    tz: str = "UTC"


FLYER_PROMPT = """This is a photo of a campus event flyer or announcement. Extract the event.
- is_event: false if this isn't an event announcement at all
- start / end: ISO 8601 with UTC offset in {tz}. Null if not printed. If the year isn't printed,
  use the next upcoming date and say so in assumptions.
- cost: exactly as printed, or null if not mentioned. Never guess a price.
- cost_amount: that price as a number (0 if it says free), null if no price is printed.
- missing: details a student would need that the flyer does NOT give
  (e.g. "price", "end time", "room number", "how to sign up")
- assumptions: anything you filled in that is not printed
Today is {today}."""

INTEREST_PROMPT = """Event: {title} — {summary} (topics: {topics})

Memories about the student (id: text):
{memories}

Which memories show the STUDENT THEMSELVES is interested in this event's topic? Only count a memory
that states the student's own interest, goal or skill. A memory about someone else (a roommate, a
friend), a loose association, or a guess does not count. Return an empty list if none qualify.
For each match give the memory id exactly as listed and a short reason quoting the memory."""

MAX_IMAGE_BYTES = 8 * 1024 * 1024


@app.post("/capture")
async def capture(image: UploadFile, context: str = Form("{}")) -> dict:
    """Flyer photo → event details → does it fit the calendar, match shared interests,
    and what's missing. Cost is reported as printed; there is no budget check yet."""
    data = await image.read()
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Image missing or larger than 8 MB")
    ctx = CaptureContext.model_validate_json(context)
    zone = _zone(ctx.tz)
    now = datetime.now(zone)

    resp = await generate(
        contents=[types.Part.from_bytes(data=data, mime_type=image.content_type or "image/jpeg"),
                  FLYER_PROMPT.format(tz=ctx.tz, today=f"{now:%A %B %d %Y}")],
        config={"response_mime_type": "application/json", "response_schema": FlyerEvent},
    )
    ev: FlyerEvent | None = resp.parsed
    if ev is None:
        raise HTTPException(502, "Couldn't read the flyer")
    if not ev.is_event:
        return {"event": ev, "conflicts": [], "interests": [], "verdict": ["This doesn't look like an event flyer."]}

    # Calendar fit: the same overlap engine as Ripple Mode.
    conflicts, assumptions = [], list(ev.assumptions)
    start = ev.start and (ev.start if ev.start.tzinfo else ev.start.replace(tzinfo=zone))
    if start:
        end = ev.end and (ev.end if ev.end.tzinfo else ev.end.replace(tzinfo=zone))
        if not end or end <= start:
            end = start + timedelta(hours=1)
            assumptions.append("Assumed it lasts 1 hour (no end time printed)")
        ev.start, ev.end = start, end
        plans = [rp.Plan(x.id, x.name, set(x.weekdays), x.hour, x.minute, x.duration, dict(x.moves))
                 for x in ctx.plans]
        calendar = [b for b in map(_block, ctx.agenda) if b]
        conflicts = rp.ripple(rp.Block("event", ev.title, start, end, "change"), None, calendar, plans, now, zone)

    # Interests: only memories the model cites by id, and only about the student.
    candidates = await search_memories(f"{ev.title} {' '.join(ev.topics)}", limit=6)
    interests = []
    if candidates:
        check = await generate(
            contents=INTEREST_PROMPT.format(
                title=ev.title, summary=ev.summary, topics=", ".join(ev.topics),
                memories="\n".join(f"{m.id}: {m.content}" for m in candidates)),
            config={"response_mime_type": "application/json", "response_schema": InterestCheck},
        )
        by_id = {m.id: m for m in candidates}
        interests = [{"memory": by_id[x.memory_id], "why": x.why}
                     for x in (check.parsed.matches if check.parsed else []) if x.memory_id in by_id]

    # The verdict is assembled from those facts, not written freely by the model.
    verdict = []
    if interests:
        verdict.append(f"Matches something you shared: “{interests[0]['memory'].content}”")
    else:
        verdict.append("Nothing you've shared links you to this topic.")
    if not start:
        verdict.append("The flyer has no date or time, so I can't check your calendar.")
    elif conflicts:
        verdict.append("Overlaps " + ", ".join(f"{c['title']} ({c['start'].astimezone(zone):%a %-I:%M %p})"
                                               for c in conflicts) + ".")
    else:
        verdict.append("Fits your calendar.")
    verdict.append(f"Cost: {ev.cost}." if ev.cost else "The flyer doesn't say what it costs.")
    plan = _planned_cost(zone, ev.cost_amount, start or now) if ev.cost_amount else None
    if plan and plan["remaining"] is None:
        verdict.append("Set a weekly budget in Money to see whether it fits.")
    elif plan and plan["after"] >= 0:
        verdict.append(f"Fits that week's budget: ${plan['remaining']:.2f} left → ${plan['after']:.2f}.")
    elif plan:
        verdict.append(f"Over that week's budget by ${-plan['after']:.2f} (${plan['remaining']:.2f} left).")
    # The cost line above already covers a missing price.
    other_missing = [m for m in ev.missing if not re.search(r"cost|price|fee", m, re.I)]
    if other_missing:
        verdict.append("Missing: " + ", ".join(other_missing) + ".")
    ev.assumptions = assumptions
    return {"event": ev, "conflicts": conflicts, "interests": interests, "verdict": verdict}


# MARK: - Memory Inspector

class MemoryEdit(BaseModel):
    content: str


@app.get("/memories")
async def list_memories() -> list[MemoryRef]:
    aid, out, page = await assistant_id(), [], 1
    while True:
        batch = (await backboard.get_memories(aid, page=page, page_size=100)).memories
        out += [MemoryRef(id=m.id, content=m.content) for m in batch]
        if len(batch) < 100:
            return out
        page += 1


@app.put("/memories/{memory_id}")
async def correct_memory(memory_id: str, body: MemoryEdit) -> MemoryRef:
    """Rewrite a memory in Backboard itself, so every later recommendation uses the correction."""
    if not body.content.strip() or len(body.content) > 1000:
        raise HTTPException(400, "Memory must be 1-1000 characters")
    try:
        m = await backboard.update_memory(await assistant_id(), memory_id, content=body.content.strip())
    except BackboardError as e:
        raise HTTPException(502, f"Backboard couldn't update it: {e}")
    return MemoryRef(id=m.id, content=m.content)


@app.delete("/memories/{memory_id}")
async def forget_memory(memory_id: str) -> dict:
    try:
        await backboard.delete_memory(await assistant_id(), memory_id)
    except BackboardError as e:
        raise HTTPException(502, f"Backboard couldn't delete it: {e}")
    return {"deleted": memory_id}


# MARK: - Money

SPEND_CATEGORIES = ["food", "groceries", "transport", "shopping", "entertainment",
                    "education", "bills", "health", "other"]


class SpendParse(BaseModel):
    is_spending: bool
    amount: float | None          # total actually paid; null when not stated
    category: Literal["food", "groceries", "transport", "shopping", "entertainment",
                      "education", "bills", "health", "other"]
    merchant: str | None
    when: datetime | None         # only when stated ("yesterday", the receipt date)
    note: str | None              # a few words: what it was


SPEND_PROMPT = """Extract ONE purchase from this {source}.
- amount: the total actually paid, as a number without a currency sign. Null if no amount is stated — never guess or estimate.
- category: the best fit from the list.
- merchant: the shop or service, if stated.
- when: ISO 8601 with UTC offset in {tz}, only if a date or day is stated ("yesterday", the receipt's date). Else null.
- note: a few words saying what it was, e.g. "lunch", "bus pass".
- is_spending: false if this isn't a purchase at all.
Now: {now}
{text}"""


class BudgetIn(BaseModel):
    weekly: float | None          # null clears the budget


def _week(zone: ZoneInfo, at: datetime | None = None) -> tuple[datetime, datetime]:
    """Monday 00:00 to the next Monday, in the user's time zone."""
    day = (at or datetime.now(zone)).astimezone(zone).date()
    start = datetime.combine(day - timedelta(days=day.weekday()), time.min, zone)
    return start, start + timedelta(days=7)


def _budget(conn) -> float | None:
    row = conn.execute("select value from prefs where key = 'weekly_budget'").fetchone()
    return float(row[0]) if row and row[0] is not None else None


def _money(zone: ZoneInfo, at: datetime | None = None) -> dict:
    """Recorded spending for the week containing `at`, against the weekly budget."""
    start, end = _week(zone, at)
    with psycopg.connect(DB) as conn:
        budget = _budget(conn)
        spent = float(conn.execute("select coalesce(sum(amount), 0) from spending where ts >= %s and ts < %s",
                                   (start, end)).fetchone()[0])
    return {"week_start": start, "budget": budget, "spent": round(spent, 2),
            "remaining": round(budget - spent, 2) if budget is not None else None}


def _money_line(zone: ZoneInfo) -> str:
    m = _money(zone)
    if m["budget"] is None:
        return f"Spent ${m['spent']:.2f} this week (no weekly budget set)."
    return f"Weekly budget ${m['budget']:.2f}: spent ${m['spent']:.2f}, ${m['remaining']:.2f} left."


@app.get("/money")
def money(tz: str = "UTC") -> dict:
    """This week's budget, totals by category and every entry."""
    zone = _zone(tz)
    start, end = _week(zone)
    with psycopg.connect(DB) as conn:
        entries = conn.execute(
            """select id, ts, amount, category, merchant, note, source from spending
               where ts >= %s and ts < %s order by ts desc""", (start, end)).fetchall()
    by_category: dict[str, float] = {}
    for _, _, amount, category, *_ in entries:
        by_category[category] = round(by_category.get(category, 0) + float(amount), 2)
    return {
        **_money(zone),
        "by_category": [{"category": c, "amount": a} for c, a in sorted(by_category.items(), key=lambda x: -x[1])],
        "entries": [{"id": str(i), "ts": ts, "amount": float(a), "category": c, "merchant": m, "note": n, "source": s}
                    for i, ts, a, c, m, n, s in entries],
    }


@app.get("/money/trend")
def money_trend(tz: str = "UTC", weeks: int = 8) -> list[dict]:
    """Spending per week and category, via Tiger's time_bucket in the user's time zone."""
    zone = _zone(tz)
    weeks = max(1, min(weeks, 26))
    start, _ = _week(zone)
    since = start - timedelta(weeks=weeks - 1)
    with psycopg.connect(DB) as conn:
        rows = conn.execute(
            """select time_bucket('1 week', ts, %s) as week, category, sum(amount)
               from spending where ts >= %s group by week, category order by week""",
            (tz, since)).fetchall()
    return [{"week_start": w, "category": c, "amount": round(float(a), 2)} for w, c, a in rows]


@app.post("/spend")
async def add_spend(text: str | None = Form(None), image: UploadFile | None = None,
                    tz: str = Form("UTC")) -> dict:
    """Record a purchase from a typed/spoken sentence or a receipt photo."""
    zone = _zone(tz)
    now = datetime.now(zone)
    if image is not None:
        data = await image.read()
        if not data or len(data) > MAX_IMAGE_BYTES:
            raise HTTPException(413, "Image missing or larger than 8 MB")
        contents = [types.Part.from_bytes(data=data, mime_type=image.content_type or "image/jpeg"),
                    SPEND_PROMPT.format(source="receipt photo", tz=tz, now=f"{now:%A %B %d %Y %H:%M}", text="")]
        source = "receipt"
    elif text and text.strip() and len(text) <= 500:
        contents = SPEND_PROMPT.format(source="note", tz=tz, now=f"{now:%A %B %d %Y %H:%M}", text=f"Note: {text}")
        source = "text"
    else:
        raise HTTPException(400, "Say what you spent, or attach a receipt")

    resp = await generate(contents=contents,
                          config={"response_mime_type": "application/json", "response_schema": SpendParse})
    p: SpendParse | None = resp.parsed
    if p is None or not p.is_spending:
        raise HTTPException(422, "That doesn't look like a purchase.")
    if p.amount is None or p.amount < 0:
        raise HTTPException(422, "How much was it? Add the amount, e.g. \"$12 on lunch\".")
    when = p.when if p.when and p.when.tzinfo else (p.when.replace(tzinfo=zone) if p.when else now)
    if when > now + timedelta(minutes=5):
        when = now   # a purchase can't be in the future; the stated day was misread
    with psycopg.connect(DB) as conn:
        new_id = conn.execute(
            """insert into spending (ts, amount, category, merchant, note, source)
               values (%s, %s, %s, %s, %s, %s) returning id""",
            (when, round(p.amount, 2), p.category, p.merchant, p.note, source)).fetchone()[0]
    return {"id": str(new_id), "ts": when, "amount": round(p.amount, 2), "category": p.category,
            "merchant": p.merchant, "note": p.note, "source": source}


@app.delete("/spend/{entry_id}")
def delete_spend(entry_id: str) -> dict:
    with psycopg.connect(DB) as conn:
        n = conn.execute("delete from spending where id::text = %s", (entry_id,)).rowcount
    if not n:
        raise HTTPException(404, "No such entry")
    return {"deleted": entry_id}


@app.put("/budget")
def set_budget(body: BudgetIn) -> dict:
    if body.weekly is not None and not 0 < body.weekly < 1_000_000:
        raise HTTPException(400, "Budget must be a positive amount")
    with psycopg.connect(DB) as conn:
        if body.weekly is None:
            conn.execute("delete from prefs where key = 'weekly_budget'")
        else:
            conn.execute("""insert into prefs (key, value) values ('weekly_budget', %s)
                            on conflict (key) do update set value = excluded.value""", (Jsonb(round(body.weekly, 2)),))
    return {"weekly": body.weekly}


def _money_context(zone: ZoneInfo) -> str:
    """Budget status and the last week of recorded spending, for Ask and the briefing."""
    with psycopg.connect(DB) as conn:
        rows = conn.execute(
            "select ts, amount, category, merchant, note from spending where ts >= %s order by ts desc limit 15",
            (datetime.now(zone) - timedelta(days=7),)).fetchall()
    recent = "\n".join(
        f"- {ts.astimezone(zone):%a %b %d}: ${float(a):.2f} {c}" + (f" at {m}" if m else "") + (f" ({n})" if n else "")
        for ts, a, c, m, n in rows) or "- nothing recorded"
    return f"{_money_line(zone)}\nRecorded spending, last 7 days (planned costs are not included):\n{recent}"
