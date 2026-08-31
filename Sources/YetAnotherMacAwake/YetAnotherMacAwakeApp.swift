import SwiftUI

@main
struct YetAnotherMacAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            Image(systemName: state.menuIconName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

struct MenuContentView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var ax = AccessibilityMonitor.shared

    var body: some View {
        Label(state.stateText, systemImage: state.menuIconName)
        .padding(.vertical, 2)

        Divider()

        HStack(spacing: 8) {
            Menu {
                ForEach(alwaysOnOptions, id: \.minutes) { option in
                    Button {
                        state.setAlwaysOn(durationMinutes: option.minutes)
                    } label: {
                        if state.store.onDurationMinutes == option.minutes {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                modeCard(isOn: state.store.mode == .on, icon: "flame.fill",
                         title: "Always On", subtitle: alwaysOnSubtitle())
            }
            .menuStyle(.borderlessButton) // no chevron; renders like the sibling cards
            .fixedSize()
            modeBox(.off, icon: "moon.fill", title: "Off", subtitle: "Allow sleep")
            modeBox(.scheduled, icon: "calendar", title: "Follow Schedule", subtitle: "Per-day windows")
        }
        .padding(.horizontal, 2)

        Divider()

        HStack(spacing: 8) {
            screenRadio(screenOff: false)
            screenRadio(screenOff: true)
        }
        .padding(.horizontal, 2)

        Divider()

        Menu {
            ForEach(pauseOptions, id: \.minutes) { option in
                Button {
                    state.pause(for: option.minutes)
                } label: {
                    if state.pausedMinutes == option.minutes {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Text("Disable for…")
        }
        // Grayed when there is nothing to disable (engine already off and not paused).
        .disabled(!state.engine.isActive && !state.isPaused)

        if state.isPaused {
            Button {
                state.resume()
            } label: {
                Label("Resume now", systemImage: "play.fill")
            }
        }

        Divider()

        // macOS 26: NSApp.sendAction("showSettingsWindow:") is rejected with
        // "Please use SettingsLink" fault. Use SettingsLink (macOS 14+) which
        // works with LSUIElement. The async activate brings an already-open
        // window front (SettingsLink alone doesn't if window is behind).
        SettingsLink {
            Text("Settings…")
        }
        .simultaneousGesture(TapGesture().onEnded {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        })

        Divider()

        Button("Quit Yet Another Mac Awake") { NSApp.terminate(nil) }
    }

    /// "Always On" durations in the card's submenu. nil = indefinitely (current
    /// behavior); the rest auto-revert to Follow Schedule when the timer expires.
    private let alwaysOnOptions: [(minutes: Int?, label: String)] = [
        (nil, "Indefinitely"),
        (60, "1 hour"),
        (120, "2 hours"),
        (240, "4 hours"),
        (360, "6 hours"),
        (720, "12 hours"),
    ]

    /// Always On card subtitle: live countdown when a timer is armed, else the
    /// static hint. Drives the visible countdown right next to the card.
    private func alwaysOnSubtitle() -> String {
        if let text = ScheduleStore.remainingText(until: state.store.onExpiresAt, now: state.now) {
            return "\(text) left"
        }
        return "Keep awake"
    }

    /// Disable durations shown in the menu submenu, in minutes. nil = indefinitely.
    private let pauseOptions: [(minutes: Int?, label: String)] = [
        (1, "1 min"),
        (5, "5 min"),
        (10, "10 min"),
        (15, "15 min"),
        (30, "30 min"),
        (60, "1 hour"),
        (nil, "Indefinitely"),
    ]

    /// Screen On/Off radio: filled circle + SF Symbol + label. Always enabled
    /// (persistent preference, pre-armed even while the engine is off or paused);
    /// selecting writes the existing display-sleep key and re-evaluates at once.
    private func screenRadio(screenOff: Bool) -> some View {
        let isSelected = screenOff == state.screenOffEnabled
        return Button {
            state.setScreenOff(screenOff)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Image(systemName: screenOff ? "moon.fill" : "sun.max.fill")
                Text(screenOff ? "Screen Can Sleep" : "Screen Stays On")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Selectable mode card: icon + title + subtitle, accent-highlighted when active.
    private func modeBox(_ mode: Mode, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = state.store.mode == mode
        return Button {
            state.setMode(mode)
        } label: {
            modeCard(isOn: isSelected, icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    /// The visual card shared by the Off/Schedule buttons and the Always On submenu label.
    private func modeCard(isOn: Bool, icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: isOn ? "checkmark.circle.fill" : icon)
                .font(.system(size: isOn ? 16 : 18, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isOn ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isOn ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isOn ? 2 : 1)
        )
        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            exit(Self.runSelfTest() ? 0 : 1)
        }
        // Keep @AppStorage defaults and plain UserDefaults reads in sync.
        UserDefaults.standard.register(defaults: [
            SettingsKey.pulseApps: "discord,slack,teams,zoom",
            SettingsKey.onlyOnAC: false,
            SettingsKey.pulseMethod: PulseMethod.auto.rawValue,
            SettingsKey.pulseIntervalSeconds: 120,
            SettingsKey.pulseKey: PulseKey.f20.rawValue,
            SettingsKey.allowDisplaySleep: false,
            SettingsKey.pulseWhenScreenOff: false,
        ])
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
        AccessibilityMonitor.shared.start()
        if CommandLine.arguments.contains("--force-on") {
            AppState.shared.engine.setActive(true)
        }
        if CommandLine.arguments.contains("--pulse-now") {
            let idleBefore = Self.idleSeconds()
            AppState.shared.engine.pulse()
            Thread.sleep(forTimeInterval: 1.5)
            let idleAfter = Self.idleSeconds()
            print("session-idle-before: \(idleBefore)s  session-idle-after: \(idleAfter)s  ax=\(AccessibilityMonitor.shared.isTrusted)")
            if idleBefore > 1 && idleAfter >= idleBefore {
                print("session idle NOT reset — grant Accessibility (Teams reads this, not HIDIdleTime)")
            }
            exit(0)
        }
    }

    private static func idleSeconds() -> CFTimeInterval {
        let anyInput = CGEventType(rawValue: UInt32(0xFFFFFFFF)) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// CLI self-test for schedule logic (no XCTest in Command Line Tools).
    private static func runSelfTest() -> Bool {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("PASS  \(name)")
            } else {
                print("FAIL  \(name)")
                failures += 1
            }
        }

        let suite = "selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return false }
        let store = ScheduleStore(defaults: defaults)

        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let sunday = cal.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let saturday = cal.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        check(store.dayIndex(for: monday) == 0, "dayIndex Monday == 0")
        check(store.dayIndex(for: sunday) == 6, "dayIndex Sunday == 6")
        check(store.dayIndex(for: saturday) == 5, "dayIndex Saturday == 5")

        let day = DaySchedule(enabled: true, startMinutes: 9 * 60, endMinutes: 18 * 60)
        let at10 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10))!
        let at9 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9))!
        let at8 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 8, minute: 59))!
        let at18 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 18))!
        check(store.inWindow(day, now: at10), "window 9-18 includes 10:00")
        check(store.inWindow(day, now: at9), "window 9-18 includes 09:00")
        check(!store.inWindow(day, now: at8), "window 9-18 excludes 08:59")
        check(!store.inWindow(day, now: at18), "window 9-18 excludes 18:00")

        let overnight = DaySchedule(enabled: true, startMinutes: 22 * 60, endMinutes: 2 * 60)
        let at23 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 23))!
        let at1 = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 1))!
        let at15 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 15))!
        check(store.inWindow(overnight, now: at23), "overnight 22-2 includes 23:00")
        check(store.inWindow(overnight, now: at1), "overnight 22-2 includes 01:00")
        check(!store.inWindow(overnight, now: at15), "overnight 22-2 excludes 15:00")

        store.mode = .off
        check(!store.activeNow(now: at10), "mode off inactive")
        store.mode = .on
        check(store.activeNow(now: at10), "mode on active")
        store.mode = .scheduled
        store.days[0] = day
        check(store.activeNow(now: at10), "scheduled active inside window")
        check(!store.activeNow(now: at8), "scheduled inactive outside window")
        let expected18 = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 18))!
        check(store.nextBoundary(now: at10) == expected18, "next boundary after 10:00 is 18:00")

        // Menu status line: Screen On/Off + battery-drop + presence-pulse suffixes
        // (pure function seam; no singletons).
        store.mode = .on
        let modeOnText = store.stateText(now: at10)   // "Awake: On"
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: false, batteryDrop: false, presencePulsePaused: false) == "Awake: On",
              "status line unchanged: mode on + screen on")
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: true, batteryDrop: false, presencePulsePaused: false) == "Awake: On · Screen off",
              "status line suffix: mode on + screen off")
        store.mode = .off
        let modeOffText = store.stateText(now: at10)  // "Awake: Off"
        check(AppState.menuStatusText(modeOffText, paused: false, screenOff: true, batteryDrop: false, presencePulsePaused: false) == "Awake: Off · Screen off",
              "status line suffix: mode off + screen off")
        store.mode = .scheduled
        let scheduledText = store.stateText(now: at10)  // "Awake: On · until 18:00"
        check(AppState.menuStatusText(scheduledText, paused: false, screenOff: true, batteryDrop: false, presencePulsePaused: false) == "Awake: On · until 18:00 · Screen off",
              "status line suffix: scheduled active + screen off")
        check(AppState.menuStatusText("Disabled · 5:00 left", paused: true, screenOff: true, batteryDrop: true, presencePulsePaused: true) == "Disabled · 5:00 left",
              "pause countdown untouched: screen off + battery + presence flags")
        check(AppState.menuStatusText("Disabled · indefinitely", paused: true, screenOff: false, batteryDrop: false, presencePulsePaused: false) == "Disabled · indefinitely",
              "indefinite pause: status text left untouched")
        check(AppState.menuStatusText("Disabled · 5:00 left", paused: true, screenOff: false, batteryDrop: true, presencePulsePaused: false) == "Disabled · 5:00 left",
              "pause countdown untouched: screen on")
        // Battery-drop suffix: awake active + AC rule on + on battery.
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: false, batteryDrop: true, presencePulsePaused: false) == "Awake: On · On battery — sleep allowed",
              "status line suffix: on battery + AC rule + active")
        // Presence-pulse-paused suffix: screen-may-sleep + app-gated pulsing, no override.
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: true, batteryDrop: false, presencePulsePaused: true) == "Awake: On · Screen off · Presence may go Away",
              "status line suffix: screen may sleep + presence pulsing")
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: true, batteryDrop: false, presencePulsePaused: false) == "Awake: On · Screen off",
              "status line suffix: screen may sleep + override on -> no presence suffix")
        // All three suffixes compose in order: Screen off, battery, presence.
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: true, batteryDrop: true, presencePulsePaused: true) == "Awake: On · Screen off · On battery — sleep allowed · Presence may go Away",
              "status line suffix: all three compose in order")

        // Assertion profile (pure function seam): settings + power state -> held set.
        check(AwakeEngine.assertionProfile(active: false, onlyOnAC: true, onACPower: false, allowDisplaySleep: true) == .none,
              "profile: inactive + battery + screen-off -> none")
        check(AwakeEngine.assertionProfile(active: false, onlyOnAC: false, onACPower: true, allowDisplaySleep: false) == .none,
              "profile: inactive -> none regardless of settings")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: false, onACPower: true, allowDisplaySleep: false) == .screenAndSystem,
              "profile: active, no battery rule, screen on -> screenAndSystem")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: false, onACPower: true, allowDisplaySleep: true) == .systemOnly,
              "profile: active, screen may sleep -> systemOnly")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: true, onACPower: true, allowDisplaySleep: false) == .screenAndSystem,
              "profile: AC rule on + AC + screen on -> screenAndSystem")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: true, onACPower: true, allowDisplaySleep: true) == .systemOnly,
              "profile: AC rule on + AC + screen may sleep -> systemOnly")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: true, onACPower: false, allowDisplaySleep: false) == .none,
              "profile: AC rule on + battery -> none")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: true, onACPower: false, allowDisplaySleep: true) == .none,
              "profile: AC rule on + battery + screen may sleep -> none")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: false, onACPower: false, allowDisplaySleep: false) == .screenAndSystem,
              "profile: no battery rule + battery -> screenAndSystem")
        check(AwakeEngine.assertionProfile(active: true, onlyOnAC: false, onACPower: false, allowDisplaySleep: true) == .systemOnly,
              "profile: no battery rule + battery + screen may sleep -> systemOnly")

        // Pulse gate (pure function seam): selected apps + running bundle IDs ->
        // pulse or skip. Fires only while at least one selected app runs; an
        // empty selection pauses the pulse entirely (never fires).
        check(AwakeEngine.pulseGate(selected: [], runningBundleIDs: ["com.tinyspeck.slackmacgap"]) == false,
              "gate: empty selection never pulses")
        check(AwakeEngine.pulseGate(selected: [], runningBundleIDs: ["com.apple.Safari", "com.tinyspeck.slackmacgap"]) == false,
              "gate: empty selection never pulses even with apps running")
        check(AwakeEngine.pulseGate(selected: [.slack], runningBundleIDs: ["com.tinyspeck.slackmacgap"]) == true,
              "gate: one selected + running -> pulse")
        check(AwakeEngine.pulseGate(selected: [.slack], runningBundleIDs: ["com.apple.Safari"]) == false,
              "gate: one selected + not running -> skip")
        check(AwakeEngine.pulseGate(selected: [.slack, .discord], runningBundleIDs: ["com.hnc.Discord"]) == true,
              "gate: two selected + one running -> pulse (any-of)")
        check(AwakeEngine.pulseGate(selected: [.slack, .discord], runningBundleIDs: ["com.apple.Safari"]) == false,
              "gate: two selected + none running -> skip")
        check(AwakeEngine.pulseGate(selected: [.teams], runningBundleIDs: ["com.microsoft.teams"]) == true,
              "gate: teams classic running -> pulse")
        check(AwakeEngine.pulseGate(selected: [.teams], runningBundleIDs: ["com.microsoft.teams2"]) == true,
              "gate: teams new running -> pulse")
        check(AwakeEngine.pulseGate(selected: [.teams], runningBundleIDs: ["com.apple.Safari"]) == false,
              "gate: teams not running -> skip")

        // Persistence encoding (pure seam): the comma-delimited raw-value string
        // round-trips, and the default selection is all four apps checked.
        check(PulseAppsSelection(Set(MessagingApp.allCases)).rawValue == "discord,slack,teams,zoom",
              "persistence: default selection encodes all four apps")
        check(PulseAppsSelection(rawValue: "discord,slack,teams,zoom").apps == Set(MessagingApp.allCases),
              "persistence: all-apps string decodes to the full selection")
        check(PulseAppsSelection(rawValue: "slack").apps == [.slack],
              "persistence: partial selection decodes")
        check(PulseAppsSelection(rawValue: "").apps.isEmpty,
              "persistence: empty string decodes to empty selection")

        // Always-On timer expiry decision (pure seam).
        check(ScheduleStore.onTimerTarget(mode: .on, expiresAt: Date().addingTimeInterval(-5), now: Date()) == .scheduled,
              "on-timer: expired Always On reverts to .scheduled")
        check(ScheduleStore.onTimerTarget(mode: .on, expiresAt: Date().addingTimeInterval(3600), now: Date()) == nil,
              "on-timer: unexpired keeps running")
        check(ScheduleStore.onTimerTarget(mode: .off, expiresAt: Date().addingTimeInterval(-5), now: Date()) == nil,
              "on-timer: non-.on mode never reverts")
        check(ScheduleStore.onTimerTarget(mode: .on, expiresAt: nil, now: Date()) == nil,
              "on-timer: infinite Always On never reverts")

        // Always-On countdown formatter (pure seam).
        check(ScheduleStore.remainingText(until: Date().addingTimeInterval(90 * 60), now: Date()) == "1h 30m",
              "remaining: 90m -> '1h 30m'")
        check(ScheduleStore.remainingText(until: Date().addingTimeInterval(45 * 60), now: Date()) == "45m",
              "remaining: 45m -> '45m'")
        check(ScheduleStore.remainingText(until: Date().addingTimeInterval(120 * 60), now: Date()) == "2h",
              "remaining: 120m -> '2h'")
        check(ScheduleStore.remainingText(until: Date(), now: Date()) == nil,
              "remaining: exactly-now -> nil (no stale 0m)")
        check(ScheduleStore.remainingText(until: Date().addingTimeInterval(-10), now: Date()) == nil,
              "remaining: expired -> nil (no stale 0m)")
        check(ScheduleStore.remainingText(until: nil, now: Date()) == nil,
              "remaining: infinite (no timer) -> nil")

        // Status line appends the countdown when an Always-On timer is armed.
        store.mode = .on
        store.onDurationMinutes = 90
        store.onExpiresAt = at10.addingTimeInterval(90 * 60)
        check(store.stateText(now: at10) == "Awake: On · 1h 30m left",
              "status: Always On with timer shows countdown")

        // Persistence round-trip for the Always-On timer (two new persisted keys).
        store.onExpiresAt = at10.addingTimeInterval(2 * 3600)
        store.save()
        let timerStore = ScheduleStore(defaults: defaults)
        check(timerStore.onDurationMinutes == 90, "persist: onDurationMinutes round-trips")
        check(timerStore.onExpiresAt != nil, "persist: onExpiresAt round-trips")
        timerStore.clearOnTimer()
        let clearedStore = ScheduleStore(defaults: defaults)
        check(clearedStore.onDurationMinutes == nil && clearedStore.onExpiresAt == nil,
              "persist: clearOnTimer clears both keys")

        defaults.removePersistentDomain(forName: suite)
        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0
    }
}

