import SwiftUI
import UIKit

struct HabitsView: View {
    @EnvironmentObject var store: HabitStore
    @State private var showingAdd = false
    @State private var editingHabit: Habit?
    @State private var pressingHabitID: UUID?
    @State private var milestoneBanner: String?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "Habits", subtitle: "Hold a habit to mark it done.")

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
                                Text("Tap New Habit below to create your first one.")
                                    .font(.bodyMedium(14))
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }

                    if !store.todaysHabits.isEmpty {
                        SectionHeader(text: "Today")
                        ForEach(Array(store.todaysHabits.enumerated()), id: \.element.id) { index, habit in
                            habitPanel(habit, active: true)
                        }
                    }

                    let restHabits = store.habits.filter { !$0.isScheduled(on: Date()) }
                    if !restHabits.isEmpty {
                        SectionHeader(text: "Off Duty")
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

                    Text("Tap to edit · hold to complete")
                        .font(.bodyRegular(11))
                        .foregroundStyle(Palette.ink.opacity(0.5))
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingAdd) { AddHabitView(habit: nil) }
        .sheet(item: $editingHabit) { habit in AddHabitView(habit: habit) }
    }

    // MARK: Pieces

    private var progressPanel: some View {
        let total = store.todaysHabits.count
        let done = store.todaysHabits.filter { $0.isCompleted(on: Date()) }.count
        return Card(fill: Palette.yellow) {
            VStack(alignment: .leading, spacing: 8) {
                Text(done == total ? "All done today!" : "\(done) OF \(total) DONE TODAY")
                    .font(.heading(22))
                    .foregroundStyle(Palette.ink)
                ProgressCapsule(progress: store.todayProgress)
            }
        }
    }


    private func habitPanel(_ habit: Habit, active: Bool) -> some View {
        let isDone = habit.isCompleted(on: Date())
        let isPressing = pressingHabitID == habit.id

        return Card(fill: isDone ? Palette.yellow.opacity(0.4) : Palette.panel) {
            HStack(spacing: 12) {
                CheckCircle(checked: isDone, pressing: isPressing)

                Text(habit.icon)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .font(.bodyMedium(16))
                        .foregroundStyle(Palette.ink)
                        .strikethrough(isDone, color: Palette.red)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(habit.streak > 0 ? "\(habit.streak)-DAY STREAK 🔥" : "NO STREAK YET")
                        .font(.heading(14))
                        .foregroundStyle(habit.streak > 0 ? Palette.red : Palette.ink.opacity(0.5))
                }
                Spacer(minLength: 4)
            }
        }
        .scaleEffect(isPressing ? 0.96 : 1)
        .animation(.easeOut(duration: 0.15), value: isPressing)
        .contentShape(Rectangle())
        .onTapGesture {
            editingHabit = habit
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            complete(habit, wasDone: isDone)
        } onPressingChanged: { pressing in
            pressingHabitID = pressing ? habit.id : nil
        }
        // The gestures above are invisible to VoiceOver and Switch Control; expose
        // the same two actions so the app's main task works without a long press.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to edit. Swipe up or down for more actions.")
        .accessibilityAction(named: isDone ? "Mark not done" : "Mark done") { complete(habit, wasDone: isDone) }
        .accessibilityAction(named: "Edit") { editingHabit = habit }
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
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            store.toggleToday(habit)
        }

        guard !wasDone else { return }

        // Hitting a streak milestone earns a bigger celebration and bonus XP.
        let newStreak = (store.habits.first { $0.id == habit.id })?.streak ?? habit.streak
        if let milestone = Gamification.milestoneReached(streak: newStreak) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.2)) {
                milestoneBanner = "\(milestone.days)-day streak · +\(milestone.bonus) XP"
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeIn(duration: 0.3)) { milestoneBanner = nil }
            }
        }

    }
}

// MARK: - Check circle (Reminders style)

struct CheckCircle: View {
    var checked: Bool
    var pressing: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(checked ? Palette.blue : Color(.tertiaryLabel), lineWidth: 2)
            if checked {
                Circle().fill(Palette.blue).padding(4)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else if pressing {
                Circle().fill(Palette.blue.opacity(0.25)).padding(4).transition(.scale)
            }
        }
        .frame(width: 28, height: 28)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: checked)
    }
}
