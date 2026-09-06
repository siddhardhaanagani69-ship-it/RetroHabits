# RetroHabits

A clean, native-iOS habit & routine tracker for iPhone, written in SwiftUI. It
tracks your daily routines with streaks and reminders, and pulls your schedule
from **Canvas** and **your iPhone calendar** into one agenda.

## What's inside

- **Habits** — daily routines with tap-to-check circles, streak counters,
  per-habit weekday schedules, and reminder notifications.
- **Agenda** — one combined timeline: Canvas assignments/course events plus
  everything synced to your iPhone calendar. Duplicates are merged automatically.
- **Stats** — a 10-week contribution grid per habit.
- **Settings** — connect your sources (details below).

Everything is stored on-device (habits as JSON). No backend, no accounts.

## 1. Run it in Xcode

1. Open `RetroHabits.xcodeproj` in Xcode (16 or newer).
2. Select the **RetroHabits** target → *Signing & Capabilities* → pick your
   personal team (your Apple ID).
3. Plug in your iPhone, pick it as the run destination, and press **Run** (⌘R).
4. If the phone blocks the app: *Settings → General → VPN & Device Management*
   → trust your developer profile. (Free Apple ID installs expire after 7 days —
   just press Run again to refresh.)

## 2. Connect Canvas (30 seconds, no sign-in)

1. Open Canvas in a browser → **Calendar** → click **Calendar Feed**
   (bottom-right of the page).
2. Copy the URL (it ends in `.ics`).
3. In the app: **Settings** tab → paste it into *Canvas calendar feed URL*.

All your Canvas assignments and course events now show up in the Agenda tab
with a Canvas tag.

## 3. iPhone calendar (covers Outlook, Teams, and everything else)

Flip on **iPhone Calendar** in the app's Settings and allow access. Any account
or app that syncs into the iOS Calendar shows up in the agenda.

**To get your Outlook events and Teams meetings** (no Azure, no admin approval):
on your iPhone go to *Settings → Apps → Calendar → Calendar Accounts →
Add Account → Microsoft Exchange*, sign in with your school email, and enable
Calendars. Your Outlook calendar — including Teams meetings — syncs to the
phone, and RetroHabits picks it all up automatically.

The same trick works for Google Calendar, subscribed feeds, and anything else
that can sync to the iPhone's calendar.

## Files

| File | What it does |
|---|---|
| `RetroHabitsApp.swift` / `ContentView.swift` | App entry + tab bar |
| `Models.swift` / `HabitStore.swift` | Habit model, streaks, persistence, notifications |
| `AgendaStore.swift` | Merges Canvas + iPhone calendar into one agenda |
| `CanvasService.swift` / `ICSParser.swift` | Canvas calendar feed |
| `AppleCalendarService.swift` | EventKit (iPhone calendars) |
| `HabitsView` / `AgendaView` / `StatsView` / `AddHabitView` / `SettingsView` | UI |

Note: `MicrosoftAuthService.swift`, `GraphService.swift`, and `Keychain.swift`
are inactive leftovers from a direct Outlook/Teams integration that the
university tenant's admin policy blocked — the iPhone calendar route above
replaces it.

## Ideas for v2

- Canvas API token support (grades, to-do items, submission status)
- Home screen widget with today's habits
- iCloud sync for habits
