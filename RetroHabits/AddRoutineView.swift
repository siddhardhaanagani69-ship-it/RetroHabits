import SwiftUI

/// Create or edit a class, shift or other weekly commitment.
struct AddRoutineView: View {
    let routine: Routine?

    @EnvironmentObject private var store: RoutineStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: Routine.Kind = .lecture
    @State private var weekdays: Set<Int> = []
    @State private var start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 11, minute: 15, second: 0, of: .now) ?? .now
    @State private var location = ""
    @State private var remind: Int? = 15
    @State private var hourlyRate: Double?
    @State private var amount: Double?
    @State private var billMonthly = true
    @State private var monthlyDay = 1
    @State private var classEnd = Routine.defaultClassEnd()

    private let reminderChoices: [Int?] = [nil, 0, 5, 10, 15, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. COSC 3380 or Library shift", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(Routine.Kind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .bill {
                    Section {
                        TextField("Amount", value: $amount, format: .currency(code: Routine.currency))
                            .keyboardType(.decimalPad)
                        Picker("Repeats", selection: $billMonthly) {
                            Text("Monthly").tag(true)
                            Text("Weekly").tag(false)
                        }
                        .pickerStyle(.segmented)
                        if billMonthly {
                            Picker("Due on day", selection: $monthlyDay) {
                                ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                    } header: {
                        Text("Bill")
                    } footer: {
                        Text("Days 1–28, so it lands in every month.")
                    }
                }

                if kind != .bill || !billMonthly {
                    Section("Repeats every") {
                        WeekdayPicker(selection: $weekdays)
                    }
                }

                if kind != .bill {
                    Section("Time") {
                        DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                        TextField("Location (optional)", text: $location)
                    }
                }

                if kind == .lecture {
                    Section {
                        DatePicker("Until", selection: $classEnd, in: Date.now..., displayedComponents: .date)
                    } footer: {
                        Text("Shows in your Agenda on class days and the day before, until this date. Four months by default.")
                    }
                }

                if kind == .shift {
                    Section {
                        TextField("Hourly pay (optional)", value: $hourlyRate, format: .currency(code: Routine.currency))
                            .keyboardType(.decimalPad)
                    } footer: {
                        Text("Shows this week's planned pay in Money. Planned pay isn't counted as earned.")
                    }
                }

                Section {
                    Picker("Remind me", selection: $remind) {
                        ForEach(kind == .bill ? [nil, 0] : reminderChoices, id: \.self) {
                            Text(kind == .bill ? Self.billReminderLabel($0) : Self.reminderLabel($0)).tag($0)
                        }
                    }
                } footer: {
                    Text(kind == .bill
                         ? "Shows on its due date in your Agenda and Money."
                         : "Repeats every week on the days you pick. Shows in your Agenda, and Ripple checks it for conflicts.")
                }

                if let routine {
                    Section {
                        Button("Delete \(kind.label)", role: .destructive) { delete(routine) }
                    }
                }
            }
            .navigationTitle(routine == nil ? "New \(kind.label)" : "Edit \(kind.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if kind == .bill { return (amount ?? 0) > 0 && (billMonthly || !weekdays.isEmpty) }
        return !weekdays.isEmpty && minutes(end) > minutes(start)
    }

    private func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func load() {
        guard let routine else { return }
        name = routine.name
        kind = routine.kind
        weekdays = routine.weekdays
        location = routine.location ?? ""
        remind = routine.remindMinutesBefore
        hourlyRate = routine.hourlyRate
        amount = routine.amount
        billMonthly = routine.monthlyDay != nil || routine.kind != .bill
        monthlyDay = routine.monthlyDay ?? 1
        classEnd = routine.endDate ?? Routine.defaultClassEnd()
        if let s = routine.start(on: .now) {
            start = s
            end = s.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
        }
    }

    private func save() {
        let startParts = Calendar.current.dateComponents([.hour, .minute], from: start)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        var saved = routine ?? Routine(name: "", weekdays: [], startHour: 0, startMinute: 0, durationMinutes: 60)
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.kind = kind
        saved.weekdays = weekdays
        saved.startHour = startParts.hour ?? 0
        saved.startMinute = startParts.minute ?? 0
        saved.durationMinutes = minutes(end) - minutes(start)
        saved.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        saved.remindMinutesBefore = remind
        saved.hourlyRate = kind == .shift ? hourlyRate : nil
        saved.amount = kind == .bill ? amount : nil
        saved.monthlyDay = kind == .bill && billMonthly ? monthlyDay : nil
        saved.endDate = kind == .lecture ? classEnd : nil
        if kind == .bill {
            // A bill is a due date: reminder at 9 AM that day, no time block.
            saved.startHour = 9
            saved.startMinute = 0
            saved.durationMinutes = 0
            saved.remindMinutesBefore = remind == nil ? nil : 0
            if billMonthly { saved.weekdays = [] }
        }
        if remind != nil {
            Task { await NotificationScheduler.shared.requestPermission() }
        }
        if routine == nil { store.add(saved) } else { store.update(saved) }
        dismiss()
    }

    private func delete(_ routine: Routine) {
        store.delete(routine)
        dismiss()
    }

    private static func billReminderLabel(_ minutes: Int?) -> String {
        minutes == nil ? "No reminder" : "On the due day, 9 AM"
    }

    private static func reminderLabel(_ minutes: Int?) -> String {
        switch minutes {
        case nil: "No reminder"
        case 0?: "When it starts"
        case let m?: "\(m) min before"
        }
    }
}
