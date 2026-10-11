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
    /// The tab before this one, so the glow can glide over from its spot.
    @State private var previousTab: AppTab = .agenda
    /// Lives here so switching tabs doesn't wipe the conversation.
    @State private var chatTurns: [AssistantService.Turn] = []

    init() {
        let initial = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .agenda
        _tab = State(initialValue: AppTab.dock.contains(initial) ? initial : .agenda)
        _sheet = State(initialValue: AppTab.dock.contains(initial) ? nil : initial)
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.dock, id: \.self) { tab in
                screen(for: tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        ZStack(alignment: .top) {
                            Palette.paper
                            GlowBackground(x: Self.glowX(tab), from: Self.glowX(previousTab))
                        }
                        .ignoresSafeArea()
                    }
                    .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
        .onChange(of: tab) { old, _ in previousTab = old }
        // Not on Ask, where it would sit on top of the message field.
        .overlay(alignment: .bottomTrailing) { if tab != .ask { plusButton } }
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

    /// Floating above the dock: Stats and Setup.
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
        .padding(.trailing, 20)
        .padding(.bottom, 72)   // sits just above the dock
    }

    /// Each tab's glow sits above its place in the dock, kept a little in from the edges.
    private static func glowX(_ tab: AppTab) -> CGFloat {
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
