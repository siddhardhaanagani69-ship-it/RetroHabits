import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var agenda: AgendaStore
    @EnvironmentObject var store: HabitStore
    @ObservedObject private var prefs = AlertPreferences.shared
    @ObservedObject private var scheduler = NotificationScheduler.shared

    private let hours = Array(0...23)

    // Body is deliberately split into small computed views — one giant
    // ViewBuilder here will blow the Swift type-checker's time budget.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ComicHeader(title: "HEADQUARTERS", subtitle: "Wire up your data sources.")
                canvasTokenPanel
                canvasFeedPanel
                calendarPanel
                alertsPanel
                digestPanel
                permissionsPanel

                Text("RETRO HABITS · ISSUE #1")
                    .font(.bangers(16))
                    .foregroundStyle(Comic.ink.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .onChange(of: prefs.deadlineAlertsEnabled) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.eventAlertsEnabled) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.dailyBriefingEnabled) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.deadlineWatchEnabled) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.briefingHour) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.watchHour) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.watchWindowDays) { _, _ in rescheduleAlerts() }
        .onChange(of: prefs.profile) { _, _ in rescheduleAlerts() }
    }

    // MARK: Canvas token

    private var canvasTokenPanel: some View {
        ComicPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CANVAS TOKEN")
                        .font(.bangers(20))
                        .foregroundStyle(Comic.red)
                    Spacer()
                    if agenda.usesCanvasAPI {
                        Text("CONNECTED")
                            .font(.bangers(12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Comic.blue))
                    }
                }

                TextField("canvas.uh.edu", text: canvasHostBinding)
                    .font(.comicLight(13))
                    .foregroundStyle(Comic.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(10)
                    .background(Comic.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))

                SecureField("Access token", text: canvasTokenBinding)
                    .font(.comicLight(13))
                    .foregroundStyle(Comic.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Comic.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))

                Text("In Canvas: Account → Settings → Approved Integrations → \"+ New Access Token\". Unlocks course names, points, and whether you've already turned things in.")
                    .font(.comicLight(12))
                    .foregroundStyle(Comic.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await agenda.refresh() }
                    } label: {
                        Text("TEST & SYNC").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))

                    if agenda.usesCanvasAPI {
                        Button {
                            agenda.canvasToken = ""
                            Task { await agenda.refresh() }
                        } label: {
                            Text("CLEAR").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle(fill: .white))
                    }
                }
            }
        }
    }

    // MARK: Canvas ICS fallback

    @ViewBuilder
    private var canvasFeedPanel: some View {
        if !agenda.usesCanvasAPI {
            ComicPanel(tilt: -0.3) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OR: CALENDAR FEED")
                        .font(.bangers(18))
                        .foregroundStyle(Comic.ink.opacity(0.7))
                    TextField("https://canvas…/feeds/calendars/….ics", text: canvasFeedBinding)
                        .font(.comicLight(13))
                        .foregroundStyle(Comic.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(10)
                        .background(Comic.paper)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))
                    Text("Simpler but thinner — due dates only. Canvas → Calendar → \"Calendar Feed\" (bottom right).")
                        .font(.comicLight(12))
                        .foregroundStyle(Comic.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: iPhone calendar

    private var calendarPanel: some View {
        ComicPanel(tilt: 0.4) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: appleCalendarBinding) {
                    Text("IPHONE CALENDAR")
                        .font(.bangers(20))
                        .foregroundStyle(Comic.blue)
                }
                .tint(Comic.red)
                Text("Pulls in every account synced to your iPhone calendar. Tip: add your school email under Settings → Apps → Calendar → Calendar Accounts and your Outlook events and Teams meetings appear here too.")
                    .font(.comicLight(12))
                    .foregroundStyle(Comic.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Alerts

    private var alertsPanel: some View {
        ComicPanel(tilt: -0.4) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ALERT WIRE")
                    .font(.bangers(20))
                    .foregroundStyle(Comic.orange)

                Toggle(isOn: $prefs.deadlineAlertsEnabled) {
                    Text("Deadline reminders")
                        .font(.comic(14))
                        .foregroundStyle(Comic.ink)
                }
                .tint(Comic.red)

                Toggle(isOn: $prefs.eventAlertsEnabled) {
                    Text("Event start reminders")
                        .font(.comic(14))
                        .foregroundStyle(Comic.ink)
                }
                .tint(Comic.red)

                Divider().overlay(Comic.ink.opacity(0.3))

                Text("HOW EARLY?")
                    .font(.bangers(15))
                    .foregroundStyle(Comic.ink.opacity(0.6))
                Picker("Lead time", selection: $prefs.profile) {
                    ForEach(LeadTimeProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                Text(prefs.profile.summary)
                    .font(.comicLight(12))
                    .foregroundStyle(Comic.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Digests

    private var digestPanel: some View {
        ComicPanel(tilt: 0.4) {
            VStack(alignment: .leading, spacing: 12) {
                Text("DAILY DIGESTS")
                    .font(.bangers(20))
                    .foregroundStyle(Comic.blue)

                Toggle(isOn: $prefs.dailyBriefingEnabled) {
                    Text("Morning briefing")
                        .font(.comic(14))
                        .foregroundStyle(Comic.ink)
                }
                .tint(Comic.red)

                if prefs.dailyBriefingEnabled {
                    hourPicker(label: "Briefing at", selection: $prefs.briefingHour)
                }

                Divider().overlay(Comic.ink.opacity(0.3))

                Toggle(isOn: $prefs.deadlineWatchEnabled) {
                    Text("Deadline watch")
                        .font(.comic(14))
                        .foregroundStyle(Comic.ink)
                }
                .tint(Comic.red)

                if prefs.deadlineWatchEnabled {
                    hourPicker(label: "Watch at", selection: $prefs.watchHour)
                    HStack {
                        Text("Look ahead")
                            .font(.comicLight(13))
                            .foregroundStyle(Comic.ink.opacity(0.7))
                        Spacer()
                        Picker("Days", selection: $prefs.watchWindowDays) {
                            ForEach([2, 3, 5, 7], id: \.self) { days in
                                Text("\(days) days").tag(days)
                            }
                        }
                        .tint(Comic.red)
                    }
                    Text("A daily nudge listing everything due in the next few days, so nothing sneaks up on you.")
                        .font(.comicLight(12))
                        .foregroundStyle(Comic.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Permissions

    private var permissionsPanel: some View {
        ComicPanel(tilt: -0.4) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PERMISSIONS")
                    .font(.bangers(20))
                    .foregroundStyle(Comic.red)
                Button {
                    Task {
                        await scheduler.requestPermission()
                        store.requestNotificationPermission()
                        await agenda.refresh()
                    }
                } label: {
                    Label("ENABLE NOTIFICATIONS", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ComicButtonStyle())
                Text("iOS doesn't let apps read other apps' notifications, so RetroHabits builds its own alerts from your Canvas and calendar data.")
                    .font(.comicLight(12))
                    .foregroundStyle(Comic.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Helpers

    private func hourPicker(label: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.comicLight(13))
                .foregroundStyle(Comic.ink.opacity(0.7))
            Spacer()
            Picker(label, selection: selection) {
                ForEach(hours, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }
            .tint(Comic.red)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return NotificationScheduler.timeFormatter.string(from: date)
    }

    private func rescheduleAlerts() {
        Task {
            await NotificationScheduler.shared.reschedule(
                items: agenda.items,
                preferences: prefs
            )
        }
    }

    private var canvasFeedBinding: Binding<String> {
        Binding(get: { agenda.canvasFeedURL }, set: { agenda.canvasFeedURL = $0 })
    }

    private var canvasHostBinding: Binding<String> {
        Binding(get: { agenda.canvasHost }, set: { agenda.canvasHost = $0 })
    }

    private var canvasTokenBinding: Binding<String> {
        Binding(get: { agenda.canvasToken }, set: { agenda.canvasToken = $0 })
    }

    private var appleCalendarBinding: Binding<Bool> {
        Binding(
            get: { agenda.appleCalendarEnabled },
            set: { newValue in
                agenda.appleCalendarEnabled = newValue
                if newValue {
                    Task {
                        _ = await AppleCalendarService.requestAccess()
                        await agenda.refresh()
                    }
                }
            }
        )
    }
}
