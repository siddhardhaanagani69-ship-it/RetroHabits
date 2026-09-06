import SwiftUI
import UIKit

struct HabitsView: View {
    @EnvironmentObject var store: HabitStore
    @State private var showingAdd = false
    @State private var editingHabit: Habit?
    @State private var burst: HeroEffect?
    @State private var pressingHabitID: UUID?
    @State private var milestoneBanner: String?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ComicHeader(title: "HABIT HQ", subtitle: "Hold a panel to smash it done!")

                    if !store.todaysHabits.isEmpty {
                        progressPanel
                    }

                    if store.habits.isEmpty {
                        ComicPanel(tilt: -0.8) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NO MISSIONS YET!")
                                    .font(.bangers(24))
                                    .foregroundStyle(Comic.red)
                                Text("Tap NEW HABIT below to create your first daily quest.")
                                    .font(.comic(14))
                                    .foregroundStyle(Comic.ink)
                            }
                        }
                    }

                    if !store.todaysHabits.isEmpty {
                        sectionLabel("TODAY", color: Comic.red)
                        ForEach(Array(store.todaysHabits.enumerated()), id: \.element.id) { index, habit in
                            habitPanel(habit, tilt: index.isMultiple(of: 2) ? 0.6 : -0.6, active: true)
                        }
                    }

                    let restHabits = store.habits.filter { !$0.isScheduled(on: Date()) }
                    if !restHabits.isEmpty {
                        sectionLabel("OFF DUTY", color: Comic.blue)
                        ForEach(Array(restHabits.enumerated()), id: \.element.id) { index, habit in
                            habitPanel(habit, tilt: index.isMultiple(of: 2) ? -0.5 : 0.5, active: false)
                                .opacity(0.75)
                        }
                    }

                    Button {
                        showingAdd = true
                    } label: {
                        Label("NEW HABIT", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                    .padding(.top, 8)

                    Text("TAP TO EDIT · HOLD TO COMPLETE · SWIPE-FREE ZONE")
                        .font(.comicLight(11))
                        .foregroundStyle(Comic.ink.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            if let burst {
                HeroBurstView(effect: burst)
                    .transition(.opacity)
            }

            if let milestoneBanner {
                VStack {
                    Spacer()
                    Text(milestoneBanner)
                        .font(.bangers(24))
                        .foregroundStyle(.white)
                        .shadow(color: Comic.ink, radius: 0, x: 2, y: 2)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Comic.ink).offset(x: 4, y: 4)
                                RoundedRectangle(cornerRadius: 10).fill(Comic.red)
                                RoundedRectangle(cornerRadius: 10).stroke(Comic.ink, lineWidth: 3)
                            }
                        )
                        .padding(.bottom, 40)
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
        return ComicPanel(fill: Comic.yellow) {
            VStack(alignment: .leading, spacing: 8) {
                Text(done == total ? "MISSION COMPLETE!" : "\(done) OF \(total) DONE TODAY")
                    .font(.bangers(22))
                    .foregroundStyle(Comic.ink)
                ComicProgressBar(progress: store.todayProgress)
            }
        }
    }

    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.bangers(22))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Comic.ink).offset(x: 3, y: 3)
                    RoundedRectangle(cornerRadius: 6).fill(color)
                    RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2)
                }
            )
            .padding(.top, 6)
    }

    private func habitPanel(_ habit: Habit, tilt: Double, active: Bool) -> some View {
        let isDone = habit.isCompleted(on: Date())
        let isPressing = pressingHabitID == habit.id

        return ComicPanel(tilt: tilt, fill: isDone ? Comic.yellow.opacity(0.4) : Comic.panel) {
            HStack(spacing: 12) {
                ComicCheckbox(checked: isDone, pressing: isPressing)

                Text(habit.icon)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name.uppercased())
                        .font(.comic(16))
                        .foregroundStyle(Comic.ink)
                        .strikethrough(isDone, color: Comic.red)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(habit.streak > 0 ? "\(habit.streak)-DAY STREAK 🔥" : "NO STREAK YET")
                        .font(.bangers(14))
                        .foregroundStyle(habit.streak > 0 ? Comic.red : Comic.ink.opacity(0.5))
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
                milestoneBanner = "\(milestone.days)-DAY STREAK! +\(milestone.bonus) XP"
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeIn(duration: 0.3)) { milestoneBanner = nil }
            }
        }

        let effect = HeroEffect.allCases.randomElement() ?? .web
        withAnimation(.easeOut(duration: 0.2)) {
            burst = effect
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeIn(duration: 0.25)) {
                burst = nil
            }
        }
    }
}

// MARK: - Comic checkbox

struct ComicCheckbox: View {
    var checked: Bool
    var pressing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Comic.ink)
                .offset(x: 2, y: 2)
            RoundedRectangle(cornerRadius: 6)
                .fill(checked ? Comic.red : Color.white)
            RoundedRectangle(cornerRadius: 6)
                .stroke(Comic.ink, lineWidth: 2.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else if pressing {
                Circle()
                    .fill(Comic.yellow)
                    .frame(width: 16, height: 16)
                    .transition(.scale)
            }
        }
        .frame(width: 34, height: 34)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: checked)
    }
}
