import SwiftUI

enum AppTab: String, CaseIterable {
    case agenda = "Agenda"
    case habits = "Routine"
    case learn = "Learn"
    case money = "Money"
    case ask = "Ask"
    case stats = "Stats"
    case settings = "Setup"

    /// In the bottom dock, Learn in the middle. Stats and Setup open from the + button.
    static let dock: [AppTab] = [.agenda, .habits, .learn, .money, .ask]

    var icon: String {
        switch self {
        case .agenda: return "calendar"
        case .habits: return "checklist"
        case .money: return "dollarsign.circle"
        case .ask: return "bubble.left.and.text.bubble.right"
        case .learn: return "brain.head.profile"
        case .stats: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    /// `-initialTab Money` at launch (screenshots, demos); Agenda otherwise.
    @State private var tab: AppTab
    /// Stats or Setup, shown as a sheet from the + button.
    @State private var sheet: AppTab?
    /// Hides the dock while typing, so the keyboard isn't stacked on top of it.
    @State private var keyboardShown = false
    /// Lives here so switching tabs doesn't wipe the conversation.
    @State private var chatTurns: [AssistantService.Turn] = []

    init() {
        let initial = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .agenda
        _tab = State(initialValue: AppTab.dock.contains(initial) ? initial : .agenda)
        _sheet = State(initialValue: AppTab.dock.contains(initial) ? nil : initial)
    }

    var body: some View {
        // Paged, so a left or right swipe moves to the next feature. Horizontal
        // scrollers inside a page (the date strip, category cards) still scroll first.
        TabView(selection: $tab) {
            ForEach(AppTab.dock, id: \.self) { tab in
                screen(for: tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Room to scroll the last item clear of the + button.
                    .contentMargins(.bottom, tab == .ask ? 0 : 64, for: .scrollContent)
                    .tag(tab)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background {
            ZStack(alignment: .top) {
                Palette.paper
                GlowBackground(x: glowX)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            if !keyboardShown {
                Dock(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        // Floats just above the dock (62 pt tall, 4 pt off the bottom) without taking a
        // row. Not on Ask, where the message field sits in that spot.
        .overlay(alignment: .bottomTrailing) {
            if tab != .ask && !keyboardShown {
                plusButton.padding(.trailing, 16).padding(.bottom, 76)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .sheet(item: $sheet) { page in
            NavigationStack {
                screen(for: page)
                    .background(Palette.paper.ignoresSafeArea())
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { sheet = nil }
                        }
                    }
            }
        }
    }

    /// Above the dock, on the right: Stats and Setup.
    private var plusButton: some View {
        Menu {
            Button("Stats", systemImage: AppTab.stats.icon) { sheet = .stats }
            Button("Setup", systemImage: AppTab.settings.icon) { sheet = .settings }
        } label: {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Palette.accent))
        }
        .accessibilityLabel("More: Stats, Setup")
    }

    /// The glow sits above the selected tab's place in the dock, a little in from the edges.
    private var glowX: CGFloat {
        let index = AppTab.dock.firstIndex(of: tab) ?? 0
        return 0.2 + 0.6 * CGFloat(index) / CGFloat(AppTab.dock.count - 1)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .agenda: AgendaView()
        case .habits: HabitsView()
        case .money: MoneyView()
        case .ask: ChatView(turns: $chatTurns)
        case .learn: LearnView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}

extension AppTab: Identifiable {
    var id: Self { self }
}

#Preview {
    ContentView()
        .environmentObject(HabitStore.shared)
        .environmentObject(AgendaStore.shared)
        .environmentObject(RoutineStore.shared)
}
