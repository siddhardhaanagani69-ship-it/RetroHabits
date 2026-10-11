import SwiftUI

/// The last two days of important email — Teams notifications included — cut
/// down to one line each. Tap one for details and a link to Gmail. Hidden when
/// Gmail isn't set up on the server.
struct InboxPanel: View {
    @EnvironmentObject var agenda: AgendaStore
    @State private var showAll = false
    @State private var selected: AssistantService.MailBrief?

    private let collapsedCount = 6
    /// Loaded with the agenda on every refresh.
    private var mails: [AssistantService.MailBrief] { agenda.mails }

    var body: some View {
        // A VStack, not a Group: a Group with no content has no views to run .task on.
        VStack(spacing: 0) {
            if !mails.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inbox")
                            .font(.heading(20))
                            .foregroundStyle(Palette.orange)
                            .padding(.bottom, 6)
                        ForEach(showAll ? mails : Array(mails.prefix(collapsedCount))) { mail in
                            Button { selected = mail } label: { row(mail) }
                                .buttonStyle(.plain)
                        }
                        if mails.count > collapsedCount {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                            } label: {
                                Text(showAll ? "Show less" : "Show \(mails.count - collapsedCount) more")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.blue)
                                    .padding(.top, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(item: $selected) { MailDetail(mail: $0) }
    }

    private func row(_ mail: AssistantService.MailBrief) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    if mail.urgency == 3 {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.red)
                    }
                    Text(mail.summary)
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !mail.action.isEmpty {
                    Label(mail.action, systemImage: "arrow.right.circle.fill")
                        .font(.bodyMedium(12))
                        .foregroundStyle(Palette.red)
                }
                if let due = mail.due {
                    Label(RippleView.range(due, mail.dueEnd), systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.orange)
                }
                Text(mail.senderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// One email: the summary, what to do, the start of the message, and a way into Gmail.
struct MailDetail: View {
    let mail: AssistantService.MailBrief
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(mail.subject).font(.headline)
                    LabeledContent("From", value: mail.senderName)
                }
                Section("Summary") {
                    Text(mail.summary)
                    if let due = mail.due {
                        Label("\(RippleView.range(due, mail.dueEnd)) · added to your agenda", systemImage: "calendar.badge.clock")
                            .foregroundStyle(Palette.orange)
                    }
                    if !mail.action.isEmpty {
                        Label(mail.action, systemImage: "arrow.right.circle.fill").foregroundStyle(Palette.red)
                    }
                }
                if !mail.excerpt.isEmpty {
                    Section("Message") {
                        Text(mail.excerpt).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let link = mail.link {
                    Section {
                        Button {
                            openURL(link)
                        } label: {
                            Label("Open in Gmail", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
