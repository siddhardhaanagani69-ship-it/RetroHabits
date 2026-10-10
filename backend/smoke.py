"""End-to-end check for /summarize. Start the server first:
    .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
then run: .venv/bin/python smoke.py
"""
import json
import time
import urllib.request

ITEMS = [
    {"id": "smoke-1", "source": "canvas", "start": "2026-10-11T23:59:00-05:00",
     "title": "Lab Report 3 - Titration [CHEM-1331-12345-FA26]",
     "notes": "Submit your lab report as a single PDF via Canvas. Late submissions lose 10% per day. "
              "See rubric attached. https://canvas.uh.edu/courses/12345/assignments/678"},
    {"id": "smoke-2", "source": "apple", "start": "2026-10-13T14:00:00-05:00",
     "title": "COSC 3380 Section 15524 - Microsoft Teams Meeting",
     "notes": "Microsoft Teams Need help? Join the meeting now Meeting ID: 284 551 909 312 Passcode: x7Kd9 "
              "Dial in by phone +1 832-555-0101 Agenda: ER diagram review before project milestone 2"},
]


def post():
    req = urllib.request.Request("http://localhost:8000/summarize", json.dumps(ITEMS).encode(),
                                 {"Content-Type": "application/json"})
    start = time.time()
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read()), time.time() - start


first, t1 = post()
for s in first:
    print(f"{s['id']}: {s['summary']!r} -> {s['action']!r} (urgency {s['urgency']}, {s['course']})")
assert {s["id"] for s in first} == {"smoke-1", "smoke-2"}, first
second, t2 = post()
assert second == first, "second call should come straight from the Tiger cache"
print(f"ok — gemini {t1:.1f}s, cached {t2:.2f}s")
