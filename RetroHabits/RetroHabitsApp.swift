import SwiftUI
import BackgroundTasks

@main
struct RetroHabitsApp: App {
    @StateObject private var habitStore = HabitStore.shared
    @StateObject private var agendaStore = AgendaStore.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    private static let refreshTaskID = "com.sid.retrohabits.refresh"

    init() {
        Self.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(habitStore)
                .environmentObject(agendaStore)
                .task {
                    await NotificationScheduler.shared.refreshAuthorizationStatus()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await AgendaStore.shared.refresh() }
            case .background:
                Self.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }

    // MARK: - Background refresh
    //
    // Keeps alerts current even when the app hasn't been opened: iOS wakes the
    // app occasionally, it re-pulls Canvas and the calendar, and reschedules
    // notifications for anything new.

    private static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handleBackgroundRefresh(refreshTask)
            }
        }
    }

    @MainActor
    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        // BGTask crashes the app if setTaskCompleted is called twice, so both
        // the refresh and the expiration handler go through this one gate.
        let completion = TaskCompletionGate(task: task)

        let work = Task { @MainActor in
            await AgendaStore.shared.refresh()
            completion.finish(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in completion.finish(success: false) }
        }
    }

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Ensures `setTaskCompleted` is delivered exactly once.
@MainActor
private final class TaskCompletionGate {
    private let task: BGTask
    private var finished = false

    init(task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
    }
}
