import SwiftUI

struct AgendaView: View {
    @EnvironmentObject var agenda: AgendaStore
    @EnvironmentObject var habits: HabitStore
    @EnvironmentObject var routines: RoutineStore
    @State private var selectedItem: AgendaItem?
    /// Habits whose box was just ticked, shown checked for a moment before sliding away.
    @State private var checking: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The day the Schedule shows; today until you tap another date circle.
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// `-agendaMode RIPPLE` at launch opens that segment; Schedule otherwise.
    @State private var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "agendaMode") ?? "") ?? .schedule
    /// Ripple's input, kept here so Campus Capture can hand it an event.
    @State private var rippleDraft = ""

    enum Mode: String, CaseIterable {
        case schedule = "Schedule"
        case ripple = "Ripple"
        case capture = "Capture"
        case alerts = "Alerts"
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "Agenda", subtitle: "Classes, deadlines and events.")
                    BriefingButton()
                    Button {
                        Task { await agenda.refresh() }
                    } label: {
                        if agenda.isLoading {
                            ProgressView().tint(Palette.ink)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .black))
                        }
                    }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(agenda.isLoading)
                    .accessibilityLabel(agenda.isLoading ? "Refreshing" : "Refresh")
                }

                // Instant swap, like a system segmented control; animating it cross-faded whole screens.
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .schedule: scheduleContent
                case .ripple: RippleView(draft: $rippleDraft)
                case .capture:
                    CaptureView { change in
                        rippleDraft = change
                        mode = .ripple
                    }
                case .alerts: AlertsSection()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { await agenda.refresh() }
        .task {
            if agenda.lastRefreshed == nil {
                await agenda.refresh()
            }
        }
        .sheet(item: $selectedItem) { item in
            EventDetailView(item: item)
        }
    }

    // MARK: Schedule

    @ViewBuilder
    private var scheduleContent: some View {
        DayStrip(selected: $selectedDay, busyDays: Set(agenda.visibleItems.map { Calendar.current.startOfDay(for: $0.start) }))

        MoneyGlance()

        ForEach(agenda.errors, id: \.self) { error in
            Card(fill: Palette.yellow) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.bodyMedium(13))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if agenda.usesCanvasAPI && (agenda.submittedCount > 0 || agenda.missingCount > 0) {
            Card(fill: Palette.yellow) {
                HStack(spacing: 14) {
                    statBlock("\(agenda.items.count)", "TOTAL", Palette.ink)
                    Divider().frame(height: 34)
                    statBlock("\(agenda.submittedCount)", "TURNED IN", Palette.accent)
                    Divider().frame(height: 34)
                    statBlock("\(agenda.missingCount)", "MISSING", Palette.red)
                }
                .frame(maxWidth: .infinity)
            }

            Toggle(isOn: $agenda.hideSubmitted.animation()) {
                Text("Hide what's turned in")
                    .font(.heading(15))
                    .foregroundStyle(Palette.ink.opacity(0.7))
            }
            .tint(Palette.red)
        }

        if noSourcesConfigured {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing connected")
                        .font(.heading(22))
                        .foregroundStyle(Palette.red)
                    Text("Add your Canvas feed or turn on iPhone Calendar in Setup to see your schedule here.")
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        dayPlan

        InboxPanel()
    }

    // MARK: Selected day

    /// Everything on the selected day: agenda items, then the habits planned for it.
    @ViewBuilder
    private var dayPlan: some View {
        // Classes get their own card (that day's, plus tomorrow's as a heads-up), not event rows.
        let classPrefixes = routines.routines.filter { $0.kind == .lecture }.map { "routine-\($0.id.uuidString)" }
        let dayItems = agenda.visibleItems.filter { item in
            Calendar.current.isDate(item.start, inSameDayAs: selectedDay)
                && !(item.source == .routine && classPrefixes.contains { item.id.hasPrefix($0) })
        }
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let classes = routines.routines(on: selectedDay).filter { $0.kind == .lecture }.map { ($0, false) }
            + routines.routines(on: nextDay).filter { $0.kind == .lecture }.map { ($0, true) }
        let isToday = Calendar.current.isDateInToday(selectedDay)
        // Today: every habit still to do (checked ones slide away). Other days: the plan.
        let dayHabits = habits.habits
            .filter { isToday ? !$0.isCompleted(on: selectedDay) : $0.isScheduled(on: selectedDay) }
            .sorted { ($0.reminderHour ?? 99, $0.reminderMinute ?? 0) < ($1.reminderHour ?? 99, $1.reminderMinute ?? 0) }
        let doneToday = isToday ? habits.habits.filter { $0.isCompleted(on: selectedDay) }.count : 0

        SectionHeader(text: dayLabel(selectedDay))

        if dayItems.isEmpty && classes.isEmpty && dayHabits.isEmpty && doneToday == 0 && !agenda.isLoading {
            Card {
                Text(isToday ? "Nothing planned today. Enjoy it." : "Nothing planned for this day.")
                    .font(.bodyMedium(14))
                    .foregroundStyle(Palette.muted)
            }
        }

        ForEach(dayItems) { item in
            Button { selectedItem = item } label: { eventPanel(item) }
                .buttonStyle(.plain)
        }

        if !classes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Classes").font(.heading(18)).foregroundStyle(Palette.ink)
                    // The same class can be on both days, so rows are keyed by position.
                    ForEach(classes.indices, id: \.self) { index in
                        classRow(classes[index].0, nextDay: classes[index].1, isToday: isToday)
                    }
                }
            }
        }

        if !dayHabits.isEmpty || doneToday > 0 {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Habits").font(.heading(18)).foregroundStyle(Palette.ink)
                    ForEach(dayHabits) { habit in
                        let ticked = checking.contains(habit.id)
                        HStack(spacing: 10) {
                            if isToday {
                                Button { complete(habit) } label: {
                                    CheckCircle(checked: ticked)
                                        .frame(width: 44, height: 44)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .disabled(ticked)
                                .accessibilityLabel("Mark \(habit.name) done today")
                            }
                            Text(habit.icon).accessibilityHidden(true)
                            Text(habit.name)
                                .font(.bodyMedium(15))
                                .foregroundStyle(Palette.ink)
                                .strikethrough(ticked, color: Palette.muted)
                            Spacer()
                            Text(plannedTime(habit, on: selectedDay))
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .transition(.asymmetric(insertion: .opacity,
                                                removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                    if doneToday > 0 {
                        Label(dayHabits.isEmpty ? "All \(doneToday) done today" : "\(doneToday) done today",
                              systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.green)
                    }
                }
            }
        }
    }

    private func classRow(_ routine: Routine, nextDay: Bool, isToday: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Routine.Kind.lecture.symbol)
                .foregroundStyle(nextDay ? Palette.muted : Palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name).font(.bodyMedium(15)).foregroundStyle(Palette.ink)
                Text([RoutineStore.time(routine), routine.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            if nextDay {
                StatusPill(text: isToday ? "Tomorrow" : "Next day", tone: .neutral)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// Ticks the box, lets the check show for a moment, then marks the habit done so
    /// its row slides off and everything below moves up. Undo lives in Routine.
    private func complete(_ habit: Habit) {
        checking.insert(habit.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
                habits.toggleToday(habit)
                checking.remove(habit.id)
            }
        }
    }

    /// A habit's time that day: a Ripple move wins over the usual reminder time.
    private func plannedTime(_ habit: Habit, on day: Date) -> String {
        if let moved = habit.moves?.values.first(where: { Calendar.current.isDate($0, inSameDayAs: day) }) {
            return Self.timeFormatter.string(from: moved)
        }
        guard let hour = habit.reminderHour, let minute = habit.reminderMinute,
              let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        else { return "Anytime" }
        return Self.timeFormatter.string(from: time)
    }

    private func statBlock(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.heading(26))
                .foregroundStyle(color)
            Text(label)
                .font(.heading(11))
                .foregroundStyle(Palette.ink.opacity(0.7))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func eventPanel(_ item: AgendaItem) -> some View {
        Card(fill: item.isSubmitted ? Palette.panel.opacity(0.65) : Palette.panel) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    Text(item.isAllDay ? "ALL\nDAY" : Self.timeFormatter.string(from: item.start))
                        .font(.heading(16))
                        .foregroundStyle(item.isMissing ? Palette.red : Palette.accent)
                        .multilineTextAlignment(.center)
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Palette.ink.opacity(0.45))
                }
                .frame(minWidth: 52)

                VStack(alignment: .leading, spacing: 4) {
                    if let course = item.courseName {
                        Text(course)
                            .font(.heading(13))
                            .foregroundStyle(item.source.tint)
                            .lineLimit(1)
                    }
                    Text(item.summary ?? item.title)
                        .font(.bodyMedium(15))
                        .foregroundStyle(item.isSubmitted ? Palette.ink.opacity(0.55) : Palette.ink)
                        .strikethrough(item.isSubmitted, color: Palette.accent)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = item.action, !item.isSubmitted {
                        Label(action, systemImage: "arrow.right.circle.fill")
                            .font(.bodyMedium(12))
                            .foregroundStyle(Palette.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        if item.urgency == 3 && !item.isSubmitted {
                            statusTag("Urgent", Palette.red)
                        }
                        if item.isSubmitted {
                            statusTag("Turned in", Palette.accent)
                        } else if item.isMissing {
                            statusTag("Missing", Palette.red)
                        }
                        if item.isGraded {
                            statusTag("Graded", Palette.ink.opacity(0.7))
                        }
                        if let points = item.pointsText {
                            Text(points)
                                .font(.bodyRegular(11))
                                .foregroundStyle(Palette.ink.opacity(0.6))
                        }
                    }

                    if let location = item.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.bodyRegular(12))
                            .foregroundStyle(Palette.ink.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                SourceTag(source: item.source)
            }
        }
    }

    private func statusTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.heading(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private var noSourcesConfigured: Bool {
        !agenda.usesCanvasAPI
            && agenda.canvasFeedURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !agenda.appleCalendarEnabled
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return Self.dayFormatter.string(from: day).uppercased()
    }
}

// MARK: - Event detail sheet

struct EventDetailView: View {
    let item: AgendaItem
    @ObservedObject private var agenda = AgendaStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let course = item.courseName {
                            Text(course)
                                .font(.heading(16))
                                .foregroundStyle(item.source.tint)
                        }
                        HStack(alignment: .top) {
                            Text(item.title)
                                .font(.heading(28))
                                .foregroundStyle(Palette.ink)
                                .minimumScaleFactor(0.6)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            SourceTag(source: item.source)
                        }
                    }
                    .padding(.top, 20)

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            if let summary = item.summary {
                                detailRow(icon: "sparkles", label: "Summary", value: summary)
                            }
                            if let action = item.action {
                                detailRow(icon: "arrow.right.circle.fill", label: "To do", value: action)
                            }
                            detailRow(icon: "clock.fill", label: "When", value: whenText)
                            detailRow(icon: item.kind.symbol, label: "Type", value: item.kind.label.capitalized)
                            if let location = item.location {
                                detailRow(icon: "mappin.and.ellipse", label: "Where", value: location)
                            }
                            if let points = item.pointsText {
                                detailRow(icon: "star.fill", label: "Worth", value: points)
                            }
                            if item.kind.isSubmittable {
                                detailRow(
                                    icon: isSubmitted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                    label: "Status",
                                    value: statusText
                                )
                            }
                        }
                    }

                    if let notes = item.notes {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Details")
                                    .font(.heading(18))
                                    .foregroundStyle(Palette.accent)
                                Text(notes)
                                    .font(.bodyRegular(14))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if item.kind.isSubmittable {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                agenda.setSubmitted(item, !isSubmitted)
                            } label: {
                                Label(isSubmitted ? "Mark as Not Turned In" : "Mark as Turned In",
                                      systemImage: isSubmitted ? "arrow.uturn.backward" : "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(fill: isSubmitted ? Palette.fill : Palette.accent,
                                                           textColor: isSubmitted ? Palette.accent : .white))
                        }
                        if let url = item.url {
                            Button {
                                openURL(url)
                            } label: {
                                Label(item.source == .canvas ? "Open in Canvas" : item.source == .email ? "Open in Gmail" : "Open Link",
                                      systemImage: "arrow.up.right.square.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                        }
                        if item.source == .apple,
                           let calendarURL = URL(string: "calshow:\(item.start.timeIntervalSinceReferenceDate)") {
                            Button {
                                openURL(calendarURL)
                            } label: {
                                Label("Open in Calendar", systemImage: "calendar")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(FilledButtonStyle(fill: Palette.accent, textColor: .white))
                        }
                        Button {
                            dismiss()
                        } label: {
                            Text("Close").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle())
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Live from the store, so the button and status flip as soon as you tap.
    private var isSubmitted: Bool {
        agenda.items.first { $0.id == item.id }?.isSubmitted ?? item.isSubmitted
    }

    private var statusText: String {
        if isSubmitted { return item.isGraded ? "Turned in and graded" : "Turned in" }
        if item.isMissing { return "Missing — not submitted" }
        return "Not turned in yet"
    }

    private var whenText: String {
        if item.isAllDay {
            return "\(AgendaView.dayFormatter.string(from: item.start)) — all day"
        }
        var text = "\(AgendaView.dayFormatter.string(from: item.start)), \(AgendaView.timeFormatter.string(from: item.start))"
        if let end = item.end {
            text += " – \(AgendaView.timeFormatter.string(from: end))"
        }
        return text
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Palette.red)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.heading(14))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                Text(value)
                    .font(.bodyMedium(14))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Date circles

/// The next two weeks as tappable circles at the top of Schedule; a dot marks days with something on them.
struct DayStrip: View {
    @Binding var selected: Date
    let busyDays: Set<Date>

    private let days: [Date] = {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(days, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                    let isToday = Calendar.current.isDateInToday(day)
                    Button {
                        selected = day   // switch days instantly, like Calendar
                    } label: {
                        VStack(spacing: 4) {
                            Text(Self.weekday.string(from: day))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : (isToday ? Palette.accent : Palette.ink))
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(isSelected ? Palette.accent : Palette.panel))
                                .overlay(Circle().stroke(isToday && !isSelected ? Palette.accent : .clear, lineWidth: 1.5))
                            Circle()
                                .fill(busyDays.contains(day) ? Palette.orange : .clear)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AgendaView.dayFormatter.string(from: day))
                }
            }
            .padding(.vertical, 4)
        }
    }
}
