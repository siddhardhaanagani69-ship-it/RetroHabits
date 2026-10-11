import SwiftUI

/// The last two days of important email — Teams notifications included — cut
/// down to one line each. Hidden when Gmail isn't set up on the server.
struct InboxPanel: View {
    @EnvironmentObject var agenda: AgendaStore
    @State private var mails: [AssistantService.MailBrief] = []

    var body: some View {
        Group {
            if !mails.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Inbox")
                            .font(.heading(20))
                            .foregroundStyle(Palette.orange)
                        ForEach(mails.prefix(6)) { mail in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .top, spacing: 6) {
                                    if mail.urgency == 3 {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(Palette.red)
                                    }
                                    Text(mail.summary)
                                        .font(.bodyMedium(14))
                                        .foregroundStyle(Palette.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if !mail.action.isEmpty {
                                    Label(mail.action, systemImage: "arrow.right.circle.fill")
                                        .font(.bodyMedium(12))
                                        .foregroundStyle(Palette.red)
                                }
                                Text(mail.senderName)
                                    .font(.heading(11))
                                    .foregroundStyle(Palette.ink.opacity(0.5))
                            }
                        }
                        if mails.count > 6 {
                            Text("+\(mails.count - 6) MORE")
                                .font(.heading(12))
                                .foregroundStyle(Palette.ink.opacity(0.5))
                        }
                    }
                }
            }
        }
        // Reload whenever the agenda refreshes (pull-to-refresh, app foregrounding).
        .task(id: agenda.lastRefreshed) {
            if let fresh = try? await AssistantService.mail() { mails = fresh }
        }
    }
}
