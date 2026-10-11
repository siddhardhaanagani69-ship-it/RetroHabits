import SwiftUI

/// Every class, from the + menu: add one, tap to edit, swipe to delete.
struct ClassScheduleView: View {
    @EnvironmentObject private var store: RoutineStore
    @State private var adding = false
    @State private var editing: Routine?

    private var classes: [Routine] {
        store.routines
            .filter { $0.kind == .lecture }
            .sorted { ($0.weekdays.min() ?? 8, $0.startHour, $0.startMinute) < ($1.weekdays.min() ?? 8, $1.startHour, $1.startMinute) }
    }

    var body: some View {
        List {
            Section {
                ForEach(classes) { routine in
                    Button { editing = routine } label: { row(routine) }
                        .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.map { classes[$0] }.forEach(store.delete)
                }
            } footer: {
                if classes.isEmpty {
                    Text("Add your classes once. Each shows in your Agenda on the day and the day before.")
                } else {
                    Text("Swipe left on a class to delete it.")
                }
            }

            Section {
                Button("Add Class", systemImage: "plus.circle.fill") { adding = true }
                    .foregroundStyle(Palette.accent)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Class Schedule")
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) { AddRoutineView(routine: nil) }
        .sheet(item: $editing) { AddRoutineView(routine: $0) }
    }

    private func row(_ routine: Routine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Routine.Kind.lecture.symbol)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name).font(.body).foregroundStyle(Palette.ink)
                Text([Self.days(routine.weekdays), RoutineStore.time(routine), routine.location]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Text(routine.endDate.map { routine.hasEnded ? "Ended \($0.formatted(date: .abbreviated, time: .omitted))"
                                                            : "Until \($0.formatted(date: .abbreviated, time: .omitted))" }
                     ?? "No end date")
                    .font(.footnote)
                    .foregroundStyle(routine.hasEnded ? Palette.red : Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the class to edit")
    }

    /// "Mon, Wed" in the user's locale, Monday-first when that's the local convention.
    static func days(_ weekdays: Set<Int>) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
            .filter(weekdays.contains)
            .map { symbols[$0 - 1] }
            .joined(separator: ", ")
    }
}
