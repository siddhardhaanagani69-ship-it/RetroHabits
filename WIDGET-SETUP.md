# Adding the home screen widget

The widget code is written and sitting in `RetroHabitsWidget/`. Xcode needs you to
create the target for it — that part can't be done from a file. It's about 5 minutes.

## 1. Create the widget target

1. Open `RetroHabits.xcodeproj`.
2. Menu bar: **File → New → Target…**
3. Pick **Widget Extension** (under iOS → Application Extension). Click **Next**.
4. Product Name: exactly **`RetroHabitsWidget`**
   - **Uncheck** "Include Live Activity"
   - **Uncheck** "Include Configuration App Intent"
5. Click **Finish**. When Xcode asks "Activate scheme?", click **Activate**.

Xcode creates a folder with template files. You're going to replace them.

## 2. Swap in the real widget code

1. In the left sidebar, open the new **RetroHabitsWidget** group.
2. Delete **every Swift file Xcode generated in that group** — right-click → **Delete**
   → **Move to Trash**. Xcode 16 usually creates three or four:
   `RetroHabitsWidget.swift`, `RetroHabitsWidgetBundle.swift`,
   `RetroHabitsWidgetControl.swift`, and sometimes `AppIntent.swift`.

   > Deleting all of them matters. The file you're about to add declares its own
   > `@main` widget bundle, and leaving Xcode's `…Bundle.swift` behind causes
   > "'main' attribute can only apply to one type in a module".

   Leave `Info.plist` and `Assets.xcassets` alone.
3. Drag `RetroHabitsWidget/RetroHabitsWidget.swift` from Finder into that group in Xcode.
   In the dialog: tick **Copy items if needed**, and under "Add to targets" tick
   **RetroHabitsWidget only** (not the main app).

## 3. Share the data between app and widget

The widget reads a file the app writes. They can only share it through an App Group.

**Enable the App Group on BOTH targets:**

1. Click the project name at the top of the sidebar → select the **RetroHabits** target
   → **Signing & Capabilities** tab → **+ Capability** → double-click **App Groups**.
2. Click the **+** under the App Groups box and enter exactly:

   ```
   group.com.sid.retrohabits
   ```

3. Now select the **RetroHabitsWidget** target → **Signing & Capabilities** →
   **+ Capability** → **App Groups** → tick the same `group.com.sid.retrohabits`.

> If you changed the app's bundle ID when you set up signing, you can use any group
> name you like — just make sure it starts with `group.` and matches in three places:
> both targets above, and the `appGroupID` constant at the top of `WidgetBridge.swift`.

**Share the bridge file with the widget:**

1. In the sidebar, click `WidgetBridge.swift` (in the RetroHabits folder).
2. Open the **File Inspector** on the right (⌥⌘1).
3. Under **Target Membership**, tick **RetroHabitsWidget** as well as RetroHabits.
4. Do the same for these files, which the bridge depends on:
   - `Models.swift`
   - `Gamification.swift`
   - `Theme.swift`

## 4. Share the fonts

1. Select `Bangers-Regular.ttf`, `ComicNeue-Regular.ttf`, and `ComicNeue-Bold.ttf`.
2. In the File Inspector, tick **RetroHabitsWidget** under Target Membership.
3. Open the widget's `Info.plist`, add a key **`UIAppFonts`** (Fonts provided by application),
   and add the three filenames as items — same as the main app's Info.plist.

If you skip this step the widget still works, it just falls back to the system font.

## 5. Run it

1. Set the scheme back to **RetroHabits** (top-left dropdown) and press **Run**.
2. Open the app once so it writes the first snapshot.
3. Long-press your home screen → **+** (top left) → search **RetroHabits** → pick a size
   → **Add Widget**.

Sizes available: small (today's progress), medium (habits + next deadlines), and a
lock-screen rectangular one.

## Troubleshooting

**Widget shows sample data (CHEM 1331, "Lab Report 3")**
The App Group isn't connected. Re-check step 3 — the group name must match exactly in
all three places, and both targets need the capability.

**"Cannot find 'WidgetBridge' in scope"**
Step 3's Target Membership wasn't applied. Tick RetroHabitsWidget for `WidgetBridge.swift`,
`Models.swift`, `Gamification.swift`, and `Theme.swift`.

**Widget is blank/white**
Open the main app once and let it refresh — the widget only draws what the app has written.

**Widget doesn't update**
It refreshes hourly, and immediately whenever you complete a habit or refresh the agenda.
iOS also throttles widget updates to save battery, so a few minutes' lag is normal.
