import SwiftUI

struct AgendaView: View {
    @EnvironmentObject var agenda: AgendaStore
    @State private var selectedItem: AgendaItem?
    @State private var mode: Mode = .schedule

    enum Mode: String, CaseIterable {
        case schedule = "SCHEDULE"
        case alerts = "ALERTS"
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
                    ComicHeader(title: "THE DAILY", subtitle: "Your missions, assembled.")
                    Button {
                        Task { await agenda.refresh() }
                    } label: {
                        if agenda.isLoading {
                            ProgressView().tint(Comic.ink)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .black))
                        }
                    }
                    .buttonStyle(ComicButtonStyle())
                    .disabled(agenda.isLoading)
                }

                Picker("Mode", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .schedule {
                    scheduleContent
                } else {
                    AlertsSection()
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
        ForEach(agenda.errors, id: \.self) { error in
            ComicPanel(fill: Comic.yellow) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.comic(13))
                    .foregroundStyle(Comic.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if agenda.usesCanvasAPI && (agenda.submittedCount > 0 || agenda.missingCount > 0) {
            ComicPanel(fill: Comic.yellow) {
                HStack(spacing: 14) {
                    statBlock("\(agenda.items.count)", "TOTAL", Comic.ink)
                    Rectangle().fill(Comic.ink).frame(width: 2, height: 34)
                    statBlock("\(agenda.submittedCount)", "TURNED IN", Comic.blue)
                    Rectangle().fill(Comic.ink).frame(width: 2, height: 34)
                    statBlock("\(agenda.missingCount)", "MISSING", Comic.red)
                }
                .frame(maxWidth: .infinity)
            }

            Toggle(isOn: $agenda.hideSubmitted.animation()) {
                Text("HIDE WHAT'S TURNED IN")
                    .font(.bangers(15))
                    .foregroundStyle(Comic.ink.opacity(0.7))
            }
            .tint(Comic.red)
        }

        if noSourcesConfigured {
            ComicPanel(tilt: -0.8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTHING CONNECTED!")
                        .font(.bangers(22))
                        .foregroundStyle(Comic.red)
                    Text("Head to SETUP and plug in your Canvas token or iPhone calendar to see your missions here.")
                        .font(.comic(14))
                        .foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if agenda.visibleItems.isEmpty && !agenda.isLoading {
            ComicPanel(tilt: 0.8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ALL CLEAR, HERO!")
                        .font(.bangers(22))
                        .foregroundStyle(Comic.blue)
                    Text(agenda.hideSubmitted && agenda.submittedCount > 0
                         ? "Everything's turned in. Enjoy it."
                         : "No upcoming events. Pull down to refresh.")
                        .font(.comic(14))
                        .foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        ForEach(agenda.itemsByDay, id: \.day) { group in
            Text(dayLabel(group.day))
                .font(.bangers(22))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Comic.ink).offset(x: 3, y: 3)
                        RoundedRectangle(cornerRadius: 6).fill(Comic.blue)
                        RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2)
                    }
                )
                .padding(.top, 6)

            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                Button {
                    selectedItem = item
                } label: {
                    eventPanel(item, tilt: index.isMultiple(of: 2) ? 0.6 : -0.6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statBlock(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.bangers(26))
                .foregroundStyle(color)
            Text(label)
                .font(.bangers(11))
                .foregroundStyle(Comic.ink.opacity(0.7))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func eventPanel(_ item: AgendaItem, tilt: Double) -> some View {
        ComicPanel(tilt: tilt, fill: item.isSubmitted ? Color.white.opacity(0.65) : Comic.panel) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    Text(item.isAllDay ? "ALL\nDAY" : Self.timeFormatter.string(from: item.start))
                        .font(.bangers(16))
                        .foregroundStyle(item.isMissing ? Comic.red : Comic.blue)
                        .multilineTextAlignment(.center)
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Comic.ink.opacity(0.45))
                }
                .frame(minWidth: 52)

                VStack(alignment: .leading, spacing: 4) {
                    if let course = item.courseName {
                        Text(course.uppercased())
                            .font(.bangers(13))
                            .foregroundStyle(item.source.tint)
                            .lineLimit(1)
                    }
                    Text(item.title)
                        .font(.comic(15))
                        .foregroundStyle(item.isSubmitted ? Comic.ink.opacity(0.55) : Comic.ink)
                        .strikethrough(item.isSubmitted, color: Comic.blue)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if item.isSubmitted {
                            statusTag("TURNED IN", Comic.blue)
                        } else if item.isMissing {
                            statusTag("MISSING", Comic.red)
                        }
                        if item.isGraded {
                            statusTag("GRADED", Comic.ink.opacity(0.7))
                        }
                        if let points = item.pointsText {
                            Text(points)
                                .font(.comicLight(11))
                                .foregroundStyle(Comic.ink.opacity(0.6))
                        }
                    }

                    if let location = item.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.comicLight(12))
                            .foregroundStyle(Comic.ink.opacity(0.65))
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
            .font(.bangers(11))
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
        if Calendar.current.isDateInToday(day) { return "TODAY" }
        if Calendar.current.isDateInTomorrow(day) { return "TOMORROW" }
        return Self.dayFormatter.string(from: day).uppercased()
    }
}

// MARK: - Event detail sheet

struct EventDetailView: View {
    let item: AgendaItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Comic.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let course = item.courseName {
                            Text(course.uppercased())
                                .font(.bangers(16))
                                .foregroundStyle(item.source.tint)
                        }
                        HStack(alignment: .top) {
                            Text(item.title)
                                .font(.bangers(28))
                                .foregroundStyle(Comic.ink)
                                .minimumScaleFactor(0.6)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            SourceTag(source: item.source)
                        }
                    }
                    .padding(.top, 20)

                    ComicPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow(icon: "clock.fill", label: "WHEN", value: whenText)
                            detailRow(icon: item.kind.symbol, label: "TYPE", value: item.kind.label.capitalized)
                            if let location = item.location {
                                detailRow(icon: "mappin.and.ellipse", label: "WHERE", value: location)
                            }
                            if let points = item.pointsText {
                                detailRow(icon: "star.fill", label: "WORTH", value: points)
                            }
                            if item.kind.isSubmittable {
                                detailRow(
                                    icon: item.isSubmitted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                    label: "STATUS",
                                    value: statusText
                                )
                            }
                        }
                    }

                    if let notes = item.notes {
                        ComicPanel(tilt: 0.4) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DETAILS")
                                    .font(.bangers(18))
                                    .foregroundStyle(Comic.blue)
                                Text(notes)
                                    .font(.comicLight(14))
                                    .foregroundStyle(Comic.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if let url = item.url {
                            Button {
                                openURL(url)
                            } label: {
                                Label(item.source == .canvas ? "OPEN IN CANVAS" : "OPEN LINK",
                                      systemImage: "arrow.up.right.square.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                        }
                        if item.source == .apple,
                           let calendarURL = URL(string: "calshow:\(item.start.timeIntervalSinceReferenceDate)") {
                            Button {
                                openURL(calendarURL)
                            } label: {
                                Label("OPEN IN CALENDAR APP", systemImage: "calendar")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ComicButtonStyle(fill: Comic.blue, textColor: .white))
                        }
                        Button {
                            dismiss()
                        } label: {
                            Text("CLOSE").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle())
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var statusText: String {
        if item.isSubmitted { return item.isGraded ? "Turned in and graded" : "Turned in" }
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
                .foregroundStyle(Comic.red)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.bangers(14))
                    .foregroundStyle(Comic.ink.opacity(0.6))
                Text(value)
                    .font(.comic(14))
                    .foregroundStyle(Comic.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
