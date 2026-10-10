"""Ripple Mode engine: given one changed commitment, find what it collides with
and where the displaced plans could go instead.

Deliberately plain code, no model calls. Every conflict is interval overlap
between a stated change and a recorded event or planned session, and every
alternative is free time in that same timeline, so each edge in the ripple
graph traces back to data. The model only parses the user's sentence (main.py).

Run this file to self-check: .venv/bin/python ripple.py
"""
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

DAY_START, DAY_END = time(6, 0), time(22, 0)  # when a displaced plan may be rescheduled
STEP = timedelta(minutes=30)
BUFFER = timedelta(minutes=15)                # breathing room around other commitments
HORIZON_DAYS = 7
MAX_OPTIONS = 3


@dataclass
class Block:
    id: str
    title: str
    start: datetime
    end: datetime
    kind: str                       # "calendar" | "plan" | "change"
    plan_id: str | None = None      # plan blocks: the habit
    original_day: str | None = None # plan blocks: "yyyy-MM-dd" of the scheduled occurrence


@dataclass
class Plan:
    id: str
    name: str
    weekdays: set[int]              # 1 = Sunday ... 7 = Saturday (iOS Calendar convention)
    hour: int
    minute: int
    duration: int = 60              # minutes
    moves: dict[str, datetime] = field(default_factory=dict)  # original day -> moved start


def ios_weekday(d: date) -> int:
    return d.isoweekday() % 7 + 1


def occurrences(plan: Plan, today: date, tz, days: int = HORIZON_DAYS) -> list[Block]:
    """Planned sessions in [today, today+days), honoring already-accepted moves."""
    length = timedelta(minutes=plan.duration)
    end_day = today + timedelta(days=days)
    out = []
    for offset in range(days):
        day = today + timedelta(days=offset)
        key = day.isoformat()
        if ios_weekday(day) in plan.weekdays and key not in plan.moves:
            start = datetime.combine(day, time(plan.hour, plan.minute), tz)
            out.append(Block(f"{plan.id}|{key}", plan.name, start, start + length, "plan", plan.id, key))
    for key, start in plan.moves.items():
        start = start.astimezone(tz)
        if today <= start.date() < end_day:
            out.append(Block(f"{plan.id}|{key}", plan.name, start, start + length, "plan", plan.id, key))
    return out


def overlaps(a: Block, b: Block, buffer: timedelta = timedelta(0)) -> bool:
    return a.start < b.end + buffer and b.start < a.end + buffer


def free_options(displaced: Block, timeline: list[Block], plan: Plan, now: datetime,
                 tz, days: int = HORIZON_DAYS) -> list[tuple[datetime, datetime]]:
    """Up to MAX_OPTIONS free slots for a displaced session: the conflict day first,
    then the nearest days outward; on each day the slot closest to the original time.
    Skips days that already have this plan, and anything in the past."""
    length = timedelta(minutes=plan.duration)
    today = now.astimezone(tz).date()
    origin = displaced.start.astimezone(tz)
    busy = [b for b in timeline if b.id != displaced.id]
    taken_days = {b.start.astimezone(tz).date() for b in busy if b.plan_id == plan.id}

    order = [0]
    for d in range(1, days):
        order += [d, -d]
    options = []
    for delta in order:
        day = origin.date() + timedelta(days=delta)
        if not today <= day < today + timedelta(days=days) or (delta and day in taken_days):
            continue
        slots = []
        t = datetime.combine(day, DAY_START, tz)
        last = datetime.combine(day, DAY_END, tz) - length
        while t <= last:
            cand = Block("candidate", plan.name, t, t + length, "plan")
            if t > now + timedelta(minutes=30) and not any(overlaps(cand, b, BUFFER) for b in busy):
                slots.append(t)
            t += STEP
        if slots:
            target = datetime.combine(day, origin.time(), tz)
            best = min(slots, key=lambda s: abs(s - target))
            options.append((best, best + length))
        if len(options) == MAX_OPTIONS:
            break
    return options


def ripple(change: Block | None, removed_id: str | None, calendar: list[Block], plans: list[Plan],
           now: datetime, tz) -> list[dict]:
    """Conflicts caused by `change` (None for a cancellation) after removing the
    item it replaces. Plan conflicts come with alternative slots; calendar
    conflicts are fixed, since the app never edits your calendar."""
    if change is None:
        return []
    today = now.astimezone(tz).date()
    # Look at least a week ahead, and always far enough to cover the changed day.
    days = max(HORIZON_DAYS, (change.end.astimezone(tz).date() - today).days + 2)
    by_plan = {p.id: p for p in plans}
    timeline = [b for b in calendar if b.id != removed_id] + [change]
    for p in plans:
        timeline += occurrences(p, today, tz, days)

    conflicts = []
    for b in timeline:
        if b is change or not overlaps(change, b):
            continue
        entry = {"id": b.id, "title": b.title, "start": b.start, "end": b.end,
                 "kind": b.kind, "movable": b.kind == "plan", "options": []}
        if b.kind == "plan":
            entry |= {"plan_id": b.plan_id, "original_day": b.original_day}
            entry["options"] = [{"start": s, "end": e}
                                for s, e in free_options(b, timeline, by_plan[b.plan_id], now, tz, days)]
        conflicts.append(entry)
    return sorted(conflicts, key=lambda c: c["start"])


if __name__ == "__main__":
    from zoneinfo import ZoneInfo
    tz = ZoneInfo("America/Chicago")
    now = datetime(2026, 10, 12, 9, 0, tzinfo=tz)                        # Monday morning
    fri = date(2026, 10, 16)
    at = lambda d, h, m=0: datetime.combine(d, time(h, m), tz)

    gym = Plan("gym", "Gym", {6}, 18, 0, 90)                             # Fridays 6:00-7:30 PM
    meeting = Block("cal-1", "Teams sync", at(fri, 19, 30), at(fri, 20, 30), "calendar")
    lab = Block("lab", "CHEM lab", at(fri, 17), at(fri, 20), "change")   # lab moved to Fri 5-8 PM

    out = ripple(lab, None, [meeting], [gym], now, tz)
    assert [c["title"] for c in out] == ["Gym", "Teams sync"], out
    g = out[0]
    assert g["movable"] and g["original_day"] == "2026-10-16"
    opts = [o["start"] for o in g["options"]]
    assert len(opts) == 3
    assert opts[0].date() == fri and opts[0] < at(fri, 17)               # same day, before the lab
    for s in opts:                                                       # nothing collides
        assert not overlaps(Block("x", "", s, s + timedelta(minutes=90), "plan"), lab, BUFFER)
    assert not out[1]["movable"] and out[1]["options"] == []             # calendar stays fixed

    # An accepted move takes the session off Friday, so the same change no longer conflicts.
    gym.moves = {"2026-10-16": at(date(2026, 10, 17), 9)}
    assert [c["title"] for c in ripple(lab, None, [meeting], [gym], now, tz)] == ["Teams sync"]

    # Moving an existing item removes its old slot from the timeline.
    old_lab = Block("lab", "CHEM lab", at(fri, 9), at(fri, 12), "calendar")
    assert ripple(lab, "lab", [old_lab], [], now, tz) == []
    # A change beyond the default week still finds the plan it collides with.
    far = Block("w", "Workshop", at(date(2026, 10, 24), 10), at(date(2026, 10, 24), 13), "change")
    sat_gym = Plan("g2", "Gym", {7}, 11, 0, 90)
    hit = ripple(far, None, [], [sat_gym], now, tz)
    assert [c["original_day"] for c in hit] == ["2026-10-24"] and hit[0]["options"], hit
    print("ripple self-check ok")
