import Foundation
import Combine

/// Single source of truth between mode/schedule and the engine.
final class AppState: ObservableObject {
    static let shared = AppState()

    let store = ScheduleStore.shared
    let engine = AwakeEngine.shared
    let ax = AccessibilityMonitor.shared

    @Published var now = Date()
    private var timer: Timer?

    private init() {}

    func start() {
        evaluate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    /// Recompute engine state from current mode + schedule.
    func evaluate() {
        engine.setActive(store.activeNow(now: Date()))
        let interval = UserDefaults.standard.integer(forKey: SettingsKey.pulseIntervalSeconds)
        engine.setPulseInterval(interval == 0 ? 120 : interval)
        now = Date()
    }

    func setMode(_ mode: Mode) {
        store.mode = mode
        store.save()
        evaluate()
    }

    var stateText: String {
        store.stateText(now: now)
    }

    var menuIconName: String {
        engine.isActive ? "flame.fill" : "flame"
    }
}
