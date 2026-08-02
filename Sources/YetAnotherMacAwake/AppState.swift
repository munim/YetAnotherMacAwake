import Foundation
import Combine

/// Single source of truth between mode/schedule and the engine.
final class AppState: ObservableObject {
    static let shared = AppState()

    let store = ScheduleStore.shared
    let engine = AwakeEngine.shared
    let ax = AccessibilityMonitor.shared

    @Published var now = Date()
    /// End of a temporary "Disable for N" pause; nil when not paused.
    @Published private(set) var pausedUntil: Date?
    /// The duration (minutes) of the active pause, used to mark the menu item.
    @Published private(set) var pausedMinutes: Int?
    private var timer: Timer?

    private init() {}

    func start() {
        evaluate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        // 1 s ticker: drives the live countdown and wakes up the moment a pause
        // expires instead of waiting for the next 30 s poll.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isPaused else { return }
            self.now = Date()
            self.evaluate()
        }
    }

    /// Recompute engine state from current mode + schedule, honoring an active pause.
    func evaluate() {
        if let until = pausedUntil, until <= Date() {
            pausedUntil = nil
            pausedMinutes = nil
        }
        engine.setActive(pausedUntil == nil ? store.activeNow(now: Date()) : false)
        let interval = UserDefaults.standard.integer(forKey: SettingsKey.pulseIntervalSeconds)
        engine.setPulseInterval(interval == 0 ? 120 : interval)
        // Re-check assertions so assertion-affecting settings (screen-off mode)
        // apply immediately instead of waiting for the next 30 s poll.
        engine.recheck()
        now = Date()
    }

    func setMode(_ mode: Mode) {
        store.mode = mode
        store.save()
        evaluate()
    }

    /// Temporarily disable the engine for `minutes`, overriding mode/schedule.
    /// In-memory only: a relaunch clears any active pause.
    func pause(for minutes: Int) {
        pausedMinutes = minutes
        pausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        evaluate()
    }

    /// End the pause early and restore mode/schedule-driven state.
    func resume() {
        pausedUntil = nil
        pausedMinutes = nil
        evaluate()
    }

    var isPaused: Bool {
        guard let until = pausedUntil else { return false }
        return until > Date()
    }

    /// Whole seconds remaining in the pause, rounded up so it never flashes 0:00 early.
    var remainingSeconds: Int {
        guard let until = pausedUntil else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSinceNow)))
    }

    var stateText: String {
        if isPaused {
            return "Disabled · \(Self.mmss(remainingSeconds)) left"
        }
        return store.stateText(now: now)
    }

    var menuIconName: String {
        if isPaused { return "pause.circle.fill" }
        return engine.isActive ? "flame.fill" : "flame"
    }

    private static func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
