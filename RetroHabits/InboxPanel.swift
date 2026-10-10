import SwiftUI

/// The last two days of important email — Teams notifications included — cut
/// down to one line each. Hidden when Gmail isn't set up on the server.
struct InboxPanel: View {
    @EnvironmentObject var agenda: AgendaStore
    @State private var mails: [AssistantService.MailBrief] = []

    var body: some View {
        Group {
            if !mails.isEmpty {
                ComicPanel(tilt: -0.4) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("INBOX BRIEF")
                            .font(.bangers(20))
                            .foregroundStyle(Comic.orange)
                        ForEach(mails.prefix(6)) { mail in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .top, spacing: 6) {
                                    if mail.urgency == 3 {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(Comic.red)
                                    }
                                    Text(mail.summary)
                                        .font(.comic(14))
                                        .foregroundStyle(Comic.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if !mail.action.isEmpty {
                                    Label(mail.action, systemImage: "arrow.right.circle.fill")
                                        .font(.comic(12))
                                        .foregroundStyle(Comic.red)
                                }
                                Text(mail.senderName.uppercased())
                                    .font(.bangers(11))
                                    .foregroundStyle(Comic.ink.opacity(0.5))
                            }
                        }
                        if mails.count > 6 {
                            Text("+\(mails.count - 6) MORE")
                                .font(.bangers(12))
                                .foregroundStyle(Comic.ink.opacity(0.5))
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
