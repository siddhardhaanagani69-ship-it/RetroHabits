import SwiftUI

enum ComicTab: String, CaseIterable {
    case agenda = "AGENDA"
    case habits = "HABITS"
    case ask = "ASK"
    case learn = "LEARN"
    case stats = "STATS"
    case settings = "SETUP"

    var icon: String {
        switch self {
        case .agenda: return "calendar"
        case .habits: return "checkmark.seal.fill"
        case .ask: return "bubble.left.and.text.bubble.right.fill"
        case .learn: return "brain.head.profile"
        case .stats: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var tab: ComicTab = .agenda
    /// Lives here so switching tabs doesn't wipe the conversation.
    @State private var chatTurns: [AssistantService.Turn] = []

    var body: some View {
        ZStack {
            Comic.paper.ignoresSafeArea()

            Group {
                switch tab {
                case .agenda: AgendaView()
                case .habits: HabitsView()
                case .ask: ChatView(turns: $chatTurns)
                case .learn: LearnView()
                case .stats: StatsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            ComicTabBar(selection: $tab)
        }
        .preferredColorScheme(.light)
    }
}

struct ComicTabBar: View {
    @Binding var selection: ComicTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ComicTab.allCases, id: \.self) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .bold))
                        Text(tab.rawValue)
                            .font(.bangers(11))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Comic.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Comic.yellow : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Comic.ink, lineWidth: isSelected ? 2.5 : 1.5)
                    )
                    .scaleEffect(isSelected ? 1.05 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Comic.paper)
                .overlay(Rectangle().frame(height: 2.5).foregroundStyle(Comic.ink), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(HabitStore.shared)
        .environmentObject(AgendaStore.shared)
}
