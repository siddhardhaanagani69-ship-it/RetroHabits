import Foundation
import Combine

/// This week's budget and recorded spending, from the server (Tiger Data), plus
/// planned money from routines: shift pay and bills. Recorded and planned amounts
/// are kept apart — a planned amount is never counted as spent or earned.
@MainActor
final class MoneyStore: ObservableObject {
    static let shared = MoneyStore()

    @Published private(set) var summary: AssistantService.MoneySummary?
    @Published private(set) var trend: [AssistantService.TrendPoint] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private init() {}

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let summary = AssistantService.money()
            async let trend = AssistantService.moneyTrend()
            (self.summary, self.trend) = try await (summary, trend)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Logs a purchase; returns it so the screen can confirm what was understood.
    func add(text: String? = nil, receiptJPEG: Data? = nil) async throws -> AssistantService.Spend {
        let entry = try await AssistantService.addSpending(text: text, receiptJPEG: receiptJPEG)
        await refresh()
        return entry
    }

    func delete(_ entry: AssistantService.Spend) async {
        do {
            try await AssistantService.deleteSpending(entry.id)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setBudget(_ weekly: Double?) async {
        do {
            try await AssistantService.setBudget(weekly)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Planned money (on the phone, from routines)

    /// This week (Mon–Sun) as dates, matching the server's budget week.
    private var thisWeek: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Pay from shifts still ahead this week (today's counts until it ends), for
    /// shifts with an hourly rate. Planned, not earned — past shifts aren't guessed at.
    var plannedShiftPay: (total: Double, shifts: Int) {
        let now = Date.now
        let shifts = thisWeek.flatMap { day in
            RoutineStore.shared.routines.filter { routine in
                guard routine.occurs(on: day), routine.payPerOccurrence != nil, let start = routine.start(on: day) else { return false }
                return start.addingTimeInterval(TimeInterval(routine.durationMinutes * 60)) > now
            }
        }
        return (shifts.compactMap(\.payPerOccurrence).reduce(0, +), shifts.count)
    }

    /// Bills due in the next 7 days, soonest first.
    var upcomingBills: [(date: Date, bill: Routine)] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).flatMap { offset -> [(Date, Routine)] in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: today) else { return [] }
            return RoutineStore.shared.routines.filter { $0.kind == .bill && $0.occurs(on: day) }.map { (day, $0) }
        }
    }
}
