"""Seed two weeks of believable history for a demo, relative to today.

    .venv/bin/python demo_seed.py          # replace any previous demo data with fresh data
    .venv/bin/python demo_seed.py --clear  # remove demo data only

Run it on demo day: the leg-day sessions land on today's weekday 7 and 14 days
ago, so the Habits tab's LAST TIME panel shows a progression and the knee memory.
Everything is tagged (logs: data.demo, memories: metadata.demo) so --clear never
touches real entries.
"""
import asyncio
import sys
from datetime import datetime, timedelta

import psycopg
from psycopg.types.json import Jsonb

import main


def ex(name, sets=None, reps=None, weight=None, unit="lb", minutes=None):
    return {"name": name, "sets": sets, "reps": reps, "weight": weight,
            "unit": unit if weight else None, "minutes": minutes}


def logs(today: datetime) -> list[tuple]:
    weekday = today.strftime("%A")
    at = lambda days: (today - timedelta(days=days)).replace(hour=18, minute=0, second=0, microsecond=0)
    return [
        (at(14), "workout", "Leg day. Squats three by eight at 125, RDLs three by ten at 85, then ten minutes on the bike.",
         {"title": "Leg Day", "mood": "good",
          "exercises": [ex("Squats", 3, 8, 125), ex("Romanian deadlifts", 3, 10, 85), ex("Bike", minutes=10)],
          "memory": f"On {weekday} did leg day: squats 3x8 at 125 lb."}),
        (at(7), "workout", "Leg day again. Squats three by eight at 135, RDLs at 95. Felt strong but my left knee was a little sore.",
         {"title": "Leg Day", "mood": "strong",
          "exercises": [ex("Squats", 3, 8, 135), ex("Romanian deadlifts", 3, 10, 95), ex("Bike", minutes=10)],
          "memory": f"On {weekday} did leg day: squats 3x8 at 135 lb, left knee a little sore."}),
        (at(5), "study", "Spent two hours on the COSC 3380 ER diagram with my team.",
         {"title": "DB Project ER Diagram", "mood": None, "exercises": [], "memory": ""}),
        (at(3), "workout", "Upper body. Bench three by eight at 115, rows three by ten at 70.",
         {"title": "Upper Body", "mood": "tired",
          "exercises": [ex("Bench press", 3, 8, 115), ex("Rows", 3, 10, 70)], "memory": ""}),
        (at(2), "mood", "Honestly stressed about the database milestone, feels like a lot this week.",
         {"title": "Stressed About DB", "mood": "stressed", "exercises": [], "memory": ""}),
        (at(1), "study", "Did an hour of SQL join practice problems.",
         {"title": "SQL Joins Practice", "mood": "focused", "exercises": [], "memory": ""}),
    ]


def memories(today: datetime) -> list[str]:
    weekday = (today - timedelta(days=7)).strftime("%A")
    return [
        f"Left knee was sore after squats last {weekday}.",
        "Is working toward squatting 155 lb by the end of the semester.",
        "Feels stressed about the COSC 3380 database project milestone.",
        "Wants to get better at SQL joins and query optimization.",
        # Campus Capture demo: the flyer should match the first and ignore the second.
        "Is interested in robotics and wants to build a robot arm.",
        "Roommate Alex is really into robotics competitions.",
    ]


async def clear() -> None:
    with psycopg.connect(main.DB) as conn:
        n = conn.execute("delete from logs where data ? 'demo'").rowcount
    aid = await main.assistant_id()
    removed, page = 0, 1
    while True:
        batch = (await main.backboard.get_memories(aid, page=page, page_size=100)).memories
        demo = [m for m in batch if (m.metadata or {}).get("demo")]
        for m in demo:
            await main.backboard.delete_memory(aid, m.id)
        removed += len(demo)
        if len(batch) < 100:
            break
        page += 0 if demo else 1  # deleting shifts later items onto this page
    print(f"cleared {n} demo logs, {removed} demo memories")


async def seed() -> None:
    await clear()
    today = datetime.now().astimezone()
    rows = logs(today)
    with psycopg.connect(main.DB) as conn:
        conn.cursor().executemany(
            "insert into logs (ts, kind, raw_text, data) values (%s, %s, %s, %s)",
            [(ts, kind, text, Jsonb({**data, "demo": True})) for ts, kind, text, data in rows],
        )
    aid = await main.assistant_id()
    for content in memories(today):
        # add_memory stores the text as-is (no LLM extraction), so the demo is predictable.
        await main.backboard.add_memory(aid, content=content, metadata={"demo": True})
    print(f"seeded {len(rows)} logs and {len(memories(today))} memories "
          f"(leg days on the last two {today:%A}s)")


if __name__ == "__main__":
    asyncio.run(clear() if "--clear" in sys.argv else seed())
