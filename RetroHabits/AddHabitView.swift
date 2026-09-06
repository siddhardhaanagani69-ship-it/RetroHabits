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

    private let icons = ["⭐️", "📚", "💪", "🏃", "💧", "🧘", "💻", "🎸", "🛏", "🍎", "✏️", "🧹"]
    private let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ZStack {
            Comic.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ComicHeader(title: habit == nil ? "NEW MISSION" : "EDIT MISSION")
                        .padding(.top, 20)

                    ComicPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NAME")
                                .font(.bangers(18))
                                .foregroundStyle(Comic.blue)
                            TextField("e.g. Read 20 minutes", text: $name)
                                .font(.comic(16))
                                .foregroundStyle(Comic.ink)
                                .padding(10)
                                .background(Comic.paper)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))
                        }
                    }

                    ComicPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ICON")
                                .font(.bangers(18))
                                .foregroundStyle(Comic.blue)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                                spacing: 8
                            ) {
                                ForEach(icons, id: \.self) { candidate in
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                            icon = candidate
                                        }
                                    } label: {
                                        Text(candidate)
                                            .font(.system(size: 22))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(icon == candidate ? Comic.yellow : Color.white)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Comic.ink, lineWidth: icon == candidate ? 2.5 : 1.5)
                                            )
                                            .scaleEffect(icon == candidate ? 1.08 : 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ComicPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("REPEAT ON")
                                .font(.bangers(18))
                                .foregroundStyle(Comic.blue)
                            HStack(spacing: 6) {
                                ForEach(1...7, id: \.self) { day in
                                    let isOn = weekdays.contains(day)
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                                            if isOn {
                                                if weekdays.count > 1 { weekdays.remove(day) }
                                            } else {
                                                weekdays.insert(day)
                                            }
                                        }
                                    } label: {
                                        Text(dayLetters[day - 1])
                                            .font(.bangers(18))
                                            .foregroundStyle(isOn ? .white : Comic.ink.opacity(0.6))
                                            .frame(maxWidth: .infinity, minHeight: 42)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(isOn ? Comic.red : Color.white)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Comic.ink, lineWidth: 2)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ComicPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $reminderOn.animation()) {
                                Text("BAT-SIGNAL REMINDER")
                                    .font(.bangers(18))
                                    .foregroundStyle(Comic.blue)
                            }
                            .tint(Comic.red)
                            if reminderOn {
                                DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                Text("You'll get a notification on each scheduled day.")
                                    .font(.comicLight(12))
                                    .foregroundStyle(Comic.ink.opacity(0.6))
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("CANCEL").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle(fill: .white))

                        Button {
                            saveAndClose()
                        } label: {
                            Text("SAVE").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
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
