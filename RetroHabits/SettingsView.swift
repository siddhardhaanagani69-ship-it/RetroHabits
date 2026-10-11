import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var agenda: AgendaStore
    @EnvironmentObject var store: HabitStore
    @ObservedObject private var prefs = AlertPreferences.shared
    @ObservedObject private var scheduler = NotificationScheduler.shared

    @AppStorage("backend_url") private var backendURL = ""
    @State private var showingMemories = false

    private let hours = Array(0...23)

    // Body is deliberately split into small computed views — one giant
    // ViewBuilder here will blow the Swift type-checker's time budget.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Setup", subtitle: "Connect your accounts and alerts.")
                assistantPanel
                canvasTokenPanel
                canvasFeedPanel
                calendarPanel
                alertsPanel
                digestPanel
                permissionsPanel

                VStack(spacing: 2) {
                    Text("Habits").font(.heading(16))
                    Text(AppInfo.tagline).font(.footnote)
                }
                .foregroundStyle(Palette.muted)
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

    // MARK: Assistant server

    private var assistantPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Assistant Server")
                    .font(.heading(20))
                    .foregroundStyle(Palette.orange)
                TextField(AssistantService.defaultURL, text: $backendURL)
                    .font(.bodyRegular(13))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(10)
                    .background(Palette.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
                SecureField("Server token (API_TOKEN)", text: tokenBinding)
                    .font(.bodyRegular(13))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Palette.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
                Button { showingMemories = true } label: {
                    Label("What I Remember About You", systemImage: "brain").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle())
                .sheet(isPresented: $showingMemories) { AllMemoriesSheet() }
                Text("Leave blank to use the Habits server. Paste the API_TOKEN from backend/.env as the token.")
                    .font(.bodyRegular(12))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Canvas token

    private var canvasTokenPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Canvas Token")
                        .font(.heading(20))
                        .foregroundStyle(Palette.red)
                    Spacer()
                    if agenda.usesCanvasAPI {
                        Text("Connected")
                            .font(.heading(12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.accent))
                    }
                }

                TextField("canvas.uh.edu", text: canvasHostBinding)
                    .font(.bodyRegular(13))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(10)
                    .background(Palette.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))

                SecureField("Access token", text: canvasTokenBinding)
                    .font(.bodyRegular(13))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Palette.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))

                Text("In Canvas: Account → Settings → Approved Integrations → \"+ New Access Token\". Unlocks course names, points, and whether you've already turned things in.")
                    .font(.bodyRegular(12))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await agenda.refresh() }
                    } label: {
                        Text("Test & Sync").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))

                    if agenda.usesCanvasAPI {
                        Button {
                            agenda.canvasToken = ""
                            Task { await agenda.refresh() }
                        } label: {
                            Text("Clear").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Canvas ICS fallback

    @ViewBuilder
    private var canvasFeedPanel: some View {
        if !agenda.usesCanvasAPI {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Or: Calendar Feed")
                        .font(.heading(18))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                    TextField("https://canvas…/feeds/calendars/….ics", text: canvasFeedBinding)
                        .font(.bodyRegular(13))
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(10)
                        .background(Palette.paper)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
                    Text("Simpler but thinner — due dates only. Canvas → Calendar → \"Calendar Feed\" (bottom right).")
                        .font(.bodyRegular(12))
                        .foregroundStyle(Palette.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: iPhone calendar

    private var calendarPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: appleCalendarBinding) {
                    Text("iPhone Calendar")
                        .font(.heading(20))
                        .foregroundStyle(Palette.accent)
                }
                .tint(Palette.red)
                Text("Pulls in every account synced to your iPhone calendar. Tip: add your school email under Settings → Apps → Calendar → Calendar Accounts and your Outlook events and Teams meetings appear here too.")
                    .font(.bodyRegular(12))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Alerts

    private var alertsPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Alerts")
                    .font(.heading(20))
                    .foregroundStyle(Palette.orange)

                Toggle(isOn: $prefs.deadlineAlertsEnabled) {
                    Text("Deadline reminders")
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.red)

                Toggle(isOn: $prefs.eventAlertsEnabled) {
                    Text("Event start reminders")
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.red)

                Divider().overlay(Palette.ink.opacity(0.3))

                Text("How early?")
                    .font(.heading(15))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                Picker("Lead time", selection: $prefs.profile) {
                    ForEach(LeadTimeProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                Text(prefs.profile.summary)
                    .font(.bodyRegular(12))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Digests

    private var digestPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Digests")
                    .font(.heading(20))
                    .foregroundStyle(Palette.accent)

                Toggle(isOn: $prefs.dailyBriefingEnabled) {
                    Text("Morning briefing")
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.red)

                if prefs.dailyBriefingEnabled {
                    hourPicker(label: "Briefing at", selection: $prefs.briefingHour)
                }

                Divider().overlay(Palette.ink.opacity(0.3))

                Toggle(isOn: $prefs.deadlineWatchEnabled) {
                    Text("Deadline watch")
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.red)

                if prefs.deadlineWatchEnabled {
                    hourPicker(label: "Watch at", selection: $prefs.watchHour)
                    HStack {
                        Text("Look ahead")
                            .font(.bodyRegular(13))
                            .foregroundStyle(Palette.ink.opacity(0.7))
                        Spacer()
                        Picker("Days", selection: $prefs.watchWindowDays) {
                            ForEach([2, 3, 5, 7], id: \.self) { days in
                                Text("\(days) days").tag(days)
                            }
                        }
                        .tint(Palette.red)
                    }
                    Text("A daily nudge listing everything due in the next few days, so nothing sneaks up on you.")
                        .font(.bodyRegular(12))
                        .foregroundStyle(Palette.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Permissions

    private var permissionsPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.heading(20))
                    .foregroundStyle(Palette.red)
                Button {
                    Task {
                        await scheduler.requestPermission()
                        store.requestNotificationPermission()
                        await agenda.refresh()
                    }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle())
                Text("iOS doesn't let apps read other apps' notifications, so Habits builds its own alerts from your Canvas and calendar data.")
                    .font(.bodyRegular(12))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Helpers

    private func hourPicker(label: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.bodyRegular(13))
                .foregroundStyle(Palette.ink.opacity(0.7))
            Spacer()
            Picker(label, selection: selection) {
                ForEach(hours, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }
            .tint(Palette.red)
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

    private var tokenBinding: Binding<String> {
        Binding(get: { AssistantService.token }, set: { AssistantService.token = $0 })
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
