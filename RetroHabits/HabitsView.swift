import SwiftUI
import UIKit

struct HabitsView: View {
    @EnvironmentObject var store: HabitStore
    @EnvironmentObject private var routines: RoutineStore
    @State private var showingAdd = false
    @State private var editingHabit: Habit?
    @State private var addingRoutine = false
    @State private var editingRoutine: Routine?
    @State private var milestoneBanner: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "Routine", subtitle: "Habits to check off, plus your weekly classes and shifts.")

                    if !store.todaysHabits.isEmpty {
                        progressPanel
                    }

                    RecallPanel()
                    VoiceLogPanel()

                    if store.habits.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No habits yet")
                                    .font(.heading(24))
                                    .foregroundStyle(Palette.red)
                                Text("Add something you want to do regularly — then tap its circle each day you do it.")
                                    .font(.bodyMedium(14))
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }

                    if !store.todaysHabits.isEmpty {
                        SectionHeader(text: "Today's habits")
                        ForEach(Array(store.todaysHabits.enumerated()), id: \.element.id) { index, habit in
                            habitPanel(habit, active: true)
                        }
                    }

                    SectionHeader(text: "Classes & shifts")
                    if routines.routines.isEmpty {
                        Card {
                            Text("Add your classes or work shifts once — they repeat every week and remind you before they start.")
                                .font(.bodyMedium(14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(routines.routines) { routine in
                        Button { editingRoutine = routine } label: { RoutineRow(routine: routine) }
                            .buttonStyle(.plain)
                    }

                    let restHabits = store.habits.filter { !$0.isScheduled(on: Date()) }
                    if !restHabits.isEmpty {
                        SectionHeader(text: "Habits not scheduled today")
                        ForEach(Array(restHabits.enumerated()), id: \.element.id) { index, habit in
                            habitPanel(habit, active: false)
                                .opacity(0.75)
                        }
                    }

                    Button {
                        showingAdd = true
                    } label: {
                        Label("New Habit", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                    .padding(.top, 8)

                    Button { addingRoutine = true } label: {
                        Label("Add Class or Shift", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle())

                    Text("Tap a circle to check off today · tap a name to edit")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            if let milestoneBanner {
                VStack {
                    Spacer()
                    Label(milestoneBanner, systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.regularMaterial))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .padding(.bottom, 24)
                        .multilineTextAlignment(.center)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingAdd) { AddHabitView(habit: nil) }
        .sheet(item: $editingHabit) { habit in AddHabitView(habit: habit) }
        .sheet(isPresented: $addingRoutine) { AddRoutineView(routine: nil) }
        .sheet(item: $editingRoutine) { AddRoutineView(routine: $0) }
    }

    // MARK: Pieces

    private var progressPanel: some View {
        let total = store.todaysHabits.count
        let done = store.todaysHabits.filter { $0.isCompleted(on: Date()) }.count
        return Card(fill: Palette.yellow) {
            VStack(alignment: .leading, spacing: 8) {
                Text(done == total ? "All done today!" : "\(done) of \(total) done today")
                    .font(.heading(22))
                    .foregroundStyle(Palette.ink)
                ProgressCapsule(progress: store.todayProgress)
            }
        }
    }


    /// The circle is a checkbox: tap it to mark today done (or undo). The rest of
    /// the row opens the editor.
    private func habitPanel(_ habit: Habit, active: Bool) -> some View {
        let isDone = habit.isCompleted(on: Date())
        let streak = habit.streak

        return Card(fill: isDone ? Palette.blue : Palette.panel) {
            HStack(spacing: 8) {
                Button { complete(habit, wasDone: isDone) } label: {
                    CheckCircle(checked: isDone)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDone ? "\(habit.name), done today" : "Mark \(habit.name) done today")

                Button { editingHabit = habit } label: {
                    HStack(spacing: 10) {
                        Text(habit.icon)
                            .font(.system(size: 26))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(habit.name)
                                .font(.bodyMedium(16))
                                .foregroundStyle(Palette.ink)
                                .strikethrough(isDone, color: .secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(isDone ? "Done today" + (streak > 1 ? " · \(streak)-day streak 🔥" : "")
                                 : streak > 0 ? "\(streak)-day streak 🔥" : "Not done yet today")
                                .font(.subheadline)
                                .foregroundStyle(isDone || streak > 0 ? Palette.red : .secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit habit")
            }
        }
        .contextMenu {
            Button {
                editingHabit = habit
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.delete(habit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func complete(_ habit: Habit, wasDone: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // No list-wide animation: only the checkbox animates (CheckCircle), so the
        // rest of the screen doesn't bounce on every tap.
        store.toggleToday(habit)

        guard !wasDone else { return }

        // Hitting a streak milestone earns a bigger celebration and bonus XP.
        let newStreak = (store.habits.first { $0.id == habit.id })?.streak ?? habit.streak
        if let milestone = Gamification.milestoneReached(streak: newStreak) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.2)) {
                milestoneBanner = "\(milestone.days)-day streak · +\(milestone.bonus) XP"
            }
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeIn(duration: 0.3)) { milestoneBanner = nil }
            }
        }

    }
}

// MARK: - Check circle (Reminders style)

struct CheckCircle: View {
    var checked: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(checked ? Palette.blue : Color(.tertiaryLabel), lineWidth: 2)
            if checked {
                Circle().fill(Palette.blue).padding(4)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 28, height: 28)
        .animation(.snappy(duration: 0.2), value: checked)   // quick, no overshoot
    }
}
