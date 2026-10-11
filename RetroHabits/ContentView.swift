import SwiftUI

enum AppTab: String, CaseIterable {
    case agenda = "Agenda"
    case habits = "Routine"
    case money = "Money"
    case ask = "Ask"
    case learn = "Learn"
    case stats = "Stats"
    case settings = "Setup"

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
    /// `-initialTab Habits` at launch (screenshots, demos); Agenda otherwise.
    @State private var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .agenda
    /// Lives here so switching tabs doesn't wipe the conversation.
    @State private var chatTurns: [AssistantService.Turn] = []

    var body: some View {
        // Native tab bar; past five tabs iOS adds its standard "More" tab.
        TabView(selection: $tab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.paper.ignoresSafeArea())
                    .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
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

#Preview {
    ContentView()
        .environmentObject(HabitStore.shared)
        .environmentObject(AgendaStore.shared)
        .environmentObject(RoutineStore.shared)
}
