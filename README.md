# Habits

**A student starter pack.**

A personal assistant for students, as a native iPhone app. Your classes,
deadlines, email, habits and memory live in one place, and the app shows how a
change in one part of your week affects the rest.

**Built with:** SwiftUI · FastAPI on Vultr · Gemini · Tiger Data · Backboard ·
ElevenLabs · Gmail API

A two-page overview is in [`Habits-README.pdf`](Habits-README.pdf). (The repo and Xcode project keep the
older name, RetroHabits.)

## Features

| Feature | What it does |
|---|---|
| **Agenda home** | Date circles for the next two weeks on top and this week's budget; tap one to see that day's plan — Canvas, iPhone Calendar (incl. Outlook/Teams meetings) and email deadlines, each rewritten by Gemini as one line. Below: a Classes card (that day's plus tomorrow's) and every habit still to do as a checkbox. |
| **Habits** | Tick one and it slides away, today's reminder for it is cancelled, and the tick is recorded for Ask. |
| **Class schedule** | From the **+** button: add, edit or swipe-to-delete classes. Each runs for a four-month term by default and shows on its day and the day before. |
| **Money** | A weekly budget. Log spending by typing, dictation or a receipt photo — with no amount it asks instead of guessing. Ripple and Capture show what a plan would leave; bills and shift pay show as planned; an 8-week trend by category. |
| **Ripple Mode** | Say what changed ("my lab moved to Friday evening") or ask "what if…". See what it collides with, free slots for any displaced habit session, and accept or reject a revised plan. |
| **Campus Capture** | Photograph an event flyer. Get the event details, whether it fits your calendar, which interests you've shared it matches, and what the flyer leaves out (e.g. the price). Save it to Calendar or plan around it. |
| **Voice log + recall** | Record "leg day, squats 3×8 at 135". It's stored as structured data; on the same weekday next time, the app shows what you did and suggests repeat / progress / ease off. |
| **Ask** | Chat by typing or tapping the mic (on-device speech-to-text). Answers use your agenda, logs, email, budget, long-term memory and 120 days of history — "when did I submit my lab?" gets a date, or "no record". Read aloud when you ask by voice. |
| **Memory Inspector** | Tap **Why?** on any suggestion to see the memories it used, then correct or forget one — the suggestion updates. |
| **Inbox & email deadlines** | Recent Gmail (incl. Teams notifications) as tappable one-liners with *Open in Gmail*. Deadlines and meetings an email states become agenda items with alerts, and Ripple checks them for conflicts. |
| **Spoken briefing** | One tap reads today's plan, urgent email and training aloud. |
| **Habits, Stats, Learn** | Streaks and reminders, XP and achievements, and an AI-engineering learning feed. |

Warm charcoal and crimson in dark mode (light mode too), swipe between tabs,
a dock with a **+** menu (Class Schedule, Stats, Setup), and a bright app icon
with a dark variant.

### Design rules

- **No invented connections.** In Ripple and Capture, Gemini only parses the
  input and has to list what it assumed. Conflicts and free slots come from
  plain overlap code in `backend/ripple.py`, which has a self-check.
- **You stay in control.** Nothing changes until you press Accept. The app
  never edits your calendar, and moving a session never marks it done.
- **Read-only email.** Gmail access is the `gmail.readonly` scope — the server
  can't send, delete or change mail.

## How it fits together

```
iPhone app (SwiftUI)
   │  HTTPS + bearer token
   ▼
FastAPI backend on Vultr (Caddy for HTTPS, systemd)
   ├── Gemini      summaries, voice notes, flyers, chat (falls back across 6 models)
   ├── Tiger Data  Postgres: summary cache, time-series voice logs
   ├── Backboard   long-term memory (search, correct, forget)
   ├── ElevenLabs  spoken briefing and replies
   └── Gmail API   recent inbox, read-only
```

## Run it

### iPhone

Plug in (or Wi-Fi pair) your iPhone and run:

```sh
scripts/phone.sh
```

It builds, installs and launches the app with the server token baked in from
`backend/.env` (the token never enters git). Builds from Xcode's Run button
don't include it — paste `API_TOKEN` into **More → Setup → Server token**
instead. Free Apple developer accounts expire installs after 7 days; just run
the script again.

In the app's **Setup**, connect your sources:

- **Canvas** — Canvas → Calendar → *Calendar Feed* → paste the `.ics` URL.
- **iPhone Calendar** — turn it on. To include Outlook and Teams meetings, add
  your school account under iPhone *Settings → Apps → Calendar → Calendar
  Accounts → Microsoft Exchange*.

### Backend

Already deployed at `https://45-76-234-93.sslip.io`. To run it locally:

```sh
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env            # fill in the keys below
.venv/bin/python init_db.py     # create the tables (safe to re-run)
.venv/bin/uvicorn main:app --port 8000
```

Push changes to the server with `backend/deploy.sh` (code) or
`backend/deploy.sh --env` (code + `.env` + Gmail token).

### Configuration (`backend/.env`)

| Key | Where to get it |
|---|---|
| `DATABASE_URL` | Tiger Cloud service connection string |
| `GEMINI_API_KEY` | aistudio.google.com → API keys |
| `BACKBOARD_API_KEY` | app.backboard.io → API Keys |
| `ELEVENLABS_API_KEY` | elevenlabs.io → Developers → API keys (starts with `sk_`) |
| `API_TOKEN` | any long random string; the app sends it to the server |

**Gmail (optional):** create a *Desktop app* OAuth client in Google Cloud and
save it as `backend/google_client.json`, add your address under *Audience →
Test users*, enable the Gmail API, then run `.venv/bin/python gmail_auth.py`
once and `deploy.sh --env`.

## Demo in 3 minutes

1. `backend/.venv/bin/python backend/demo_seed.py` — two weeks of history and
   sample memories (`--clear` removes only the demo data).
2. In the app, create a **Gym** habit on Fridays with a 6:00 PM reminder, 90 min.
3. **Capture** a robotics-workshop flyer → it matches your interest, flags the
   Friday gym clash and the missing price.
4. **Plan around it** → Ripple shows the gym conflict and free slots → **Accept**.
5. Tap **Why?** → correct "I like robotics" to "that was my roommate" → the
   re-check updates the verdict.

## Project layout

| Path | What it is |
|---|---|
| `RetroHabits/` | The SwiftUI app. `AssistantService.swift` talks to the backend; `AgendaView`, `RippleView`, `CaptureView`, `ChatView`, `MemoryInspector`, `InboxPanel` are the main screens. |
| `backend/main.py` | FastAPI server: summaries, voice log, recall, chat, ripple, capture, memory, mail, speech. |
| `backend/ripple.py` | Deterministic conflict and free-slot engine (`python ripple.py` runs its self-check). |
| `backend/schema.sql`, `init_db.py` | Tiger Data tables. |
| `backend/demo_seed.py`, `smoke.py` | Demo data and an end-to-end check. |
| `scripts/phone.sh`, `scripts/app-icon.swift` | Install on iPhone; regenerate the app icon. |
| `RetroHabitsWidget/` | Home-screen widget code (add its Xcode target per `WIDGET-SETUP.md`). |

## Known limits

- No money or budget features yet.
- Gemini's free tier allows about 120 requests a day across the fallback
  models; enable billing before a heavy demo.
- Gmail sign-in in Google's Testing mode expires after 7 days — rerun
  `gmail_auth.py` and `deploy.sh --env`, or publish the consent screen.
