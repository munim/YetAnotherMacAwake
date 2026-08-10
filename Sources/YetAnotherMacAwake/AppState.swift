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
        // expires or an Always-On timer runs out, instead of waiting for the 30 s poll.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isPaused || self.hasActiveOnTimer else { return }
            self.now = Date()
            self.evaluate()
        }
    }

    /// True while an Always-On timer is armed (a finite `.on` session).
    var hasActiveOnTimer: Bool {
        store.mode == .on && store.onExpiresAt != nil
    }

    /// Recompute engine state from current mode + schedule, honoring an active pause.
    func evaluate() {
        if let until = pausedUntil, until <= Date() {
            pausedUntil = nil
            pausedMinutes = nil
        }
        // Always-On timer expiry: move the mode to its target (Follow Schedule)
        // before computing active state. This also catches a persisted timer that
        // expired while the app wasn't running (relaunch, crash).
        if let target = ScheduleStore.onTimerTarget(mode: store.mode, expiresAt: store.onExpiresAt, now: Date()) {
            store.mode = target
            store.onExpiresAt = nil
            store.onDurationMinutes = nil
            store.save()
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
        // Leaving Always On cancels any pending timer so it can't fire later.
        if mode != .on {
            store.clearOnTimer()
        }
        store.save()
        evaluate()
    }

    /// Arm "Always On" for a finite duration, or indefinitely (nil).
    /// Persists the chosen duration + expiry so the timer survives a relaunch.
    func setAlwaysOn(durationMinutes: Int?) {
        store.mode = .on
        store.onDurationMinutes = durationMinutes
        if let minutes = durationMinutes {
            store.onExpiresAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            store.onExpiresAt = nil
        }
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
        let paused = isPaused
        let base = paused
            ? "Disabled · \(Self.mmss(remainingSeconds)) left"
            : store.stateText(now: now)
        let defaults = UserDefaults.standard
        // Battery-drop: awake active but the AC-only rule drops assertions.
        let batteryDrop = !paused && engine.isActive
            && defaults.bool(forKey: SettingsKey.onlyOnAC)
            && !engine.onACPower
        // Presence-pulse-paused: screen-may-sleep pauses the pulse while the
        // user has opted into app gating (checked at least one app), and no
        // override is set. An empty selection pauses the pulse entirely, so no
        // warning.
        let presencePulsePaused = !paused && engine.isActive
            && PulseAppsSelection.fromDefaults(defaults)
                .presenceMayGoAway(screenOff: screenOffEnabled,
                                   overrideEnabled: defaults.bool(forKey: SettingsKey.pulseWhenScreenOff))
        return Self.menuStatusText(base, paused: paused, screenOff: screenOffEnabled,
                                   batteryDrop: batteryDrop, presencePulsePaused: presencePulsePaused)
    }

    var menuIconName: String {
        if isPaused { return "pause.circle.fill" }
        return engine.isActive ? "flame.fill" : "flame"
    }

    /// Persisted display-sleep preference (`settings.allowDisplaySleep`); Screen
    /// On radios read it directly so the menu mirrors Settings with one source.
    var screenOffEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.allowDisplaySleep)
    }

    /// Flip display behavior from the menu radios: persist the existing key and
    /// re-evaluate so the engine swaps assertion types immediately (no 30 s poll).
    func setScreenOff(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKey.allowDisplaySleep)
        evaluate()
    }

    /// Pure status-line formatter (menu + CLI self-test seam). Appends the
    /// " · Screen off" suffix, then the battery-drop suffix when the AC-only
    /// rule drops assertions, then the presence-pulse-paused warning. Pause
    /// countdown text is left untouched so a pause stays unambiguous.
    static func menuStatusText(_ base: String, paused: Bool, screenOff: Bool,
                               batteryDrop: Bool, presencePulsePaused: Bool) -> String {
        if paused { return base }
        var text = base
        if screenOff { text += " · Screen off" }
        if batteryDrop { text += " · On battery — sleep allowed" }
        if presencePulsePaused { text += " · Presence may go Away" }
        return text
    }

    private static func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
