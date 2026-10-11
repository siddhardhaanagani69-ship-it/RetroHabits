import SwiftUI

struct AddHabitView: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) private var dismiss

    let habit: Habit?

    @State private var name: String = ""
    @State private var icon: String = "⭐️"
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    @State private var reminderOn: Bool = false
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var duration: Int = 60

    private let icons = ["⭐️", "📚", "💪", "🏃", "💧", "🧘", "💻", "🎸", "🛏", "🍎", "✏️", "🧹"]
    private let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(title: habit == nil ? "New Habit" : "Edit Habit")
                        .padding(.top, 20)

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.heading(18))
                                .foregroundStyle(Palette.accent)
                            TextField("e.g. Read 20 minutes", text: $name)
                                .font(.bodyMedium(16))
                                .foregroundStyle(Palette.ink)
                                .padding(10)
                                .background(Palette.paper)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Icon")
                                .font(.heading(18))
                                .foregroundStyle(Palette.accent)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                                spacing: 8
                            ) {
                                ForEach(icons, id: \.self) { candidate in
                                    Button {
                                        icon = candidate
                                    } label: {
                                        Text(candidate)
                                            .font(.system(size: 22))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(icon == candidate ? Palette.yellow : Palette.panel)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(icon == candidate ? Palette.accent : Palette.hairline, lineWidth: icon == candidate ? 2 : 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Repeat on")
                                .font(.heading(18))
                                .foregroundStyle(Palette.accent)
                            HStack(spacing: 6) {
                                ForEach(1...7, id: \.self) { day in
                                    let isOn = weekdays.contains(day)
                                    Button {
                                        if isOn {
                                            if weekdays.count > 1 { weekdays.remove(day) }
                                        } else {
                                            weekdays.insert(day)
                                        }
                                    } label: {
                                        Text(dayLetters[day - 1])
                                            .font(.heading(18))
                                            .foregroundStyle(isOn ? .white : Palette.ink.opacity(0.6))
                                            .frame(maxWidth: .infinity, minHeight: 42)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(isOn ? Palette.red : Palette.panel)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Palette.hairline, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $reminderOn.animation()) {
                                Text("Reminder")
                                    .font(.heading(18))
                                    .foregroundStyle(Palette.accent)
                            }
                            .tint(Palette.red)
                            if reminderOn {
                                DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                Stepper(value: $duration, in: 15...240, step: 15) {
                                    Text("Takes about \(duration) min")
                                        .font(.heading(16))
                                        .foregroundStyle(Palette.ink)
                                }
                                Text("You'll get a notification on each scheduled day. This time is also the habit's planned slot — Ripple Mode checks it for conflicts.")
                                    .font(.bodyRegular(12))
                                    .foregroundStyle(Palette.ink.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle())

                        Button {
                            saveAndClose()
                        } label: {
                            Text("Save").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear { populateFromExisting() }
    }

    private func populateFromExisting() {
        guard let habit else { return }
        name = habit.name
        icon = habit.icon
        weekdays = habit.scheduledWeekdays
        duration = habit.duration
        if let hour = habit.reminderHour, let minute = habit.reminderMinute {
            reminderOn = true
            reminderTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
    }

    private func saveAndClose() {
        var saved = habit ?? Habit(name: "")
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.icon = icon
        saved.scheduledWeekdays = weekdays
        saved.durationMinutes = duration
        if reminderOn {
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            saved.reminderHour = components.hour
            saved.reminderMinute = components.minute
            store.requestNotificationPermission()
        } else {
            saved.reminderHour = nil
            saved.reminderMinute = nil
        }
        if habit == nil {
            store.add(saved)
        } else {
            store.update(saved)
        }
        dismiss()
    }
}
