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

    var body: some View {
        Label(state.stateText, systemImage: state.menuIconName)
        .padding(.vertical, 2)

        Divider()

        HStack(spacing: 8) {
            modeBox(.on, icon: "flame.fill", title: "Always On", subtitle: "Keep awake")
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

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Yet Another Mac Awake") { NSApp.terminate(nil) }
    }

    /// Disable durations shown in the menu submenu, in minutes.
    private let pauseOptions: [(minutes: Int, label: String)] = [
        (1, "1 min"),
        (5, "5 min"),
        (10, "10 min"),
        (15, "15 min"),
        (30, "30 min"),
        (60, "1 hour"),
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
        VStack(spacing: 4) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                .font(.system(size: isSelected ? 16 : 18, weight: .medium))
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
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            exit(Self.runSelfTest() ? 0 : 1)
        }
        // Keep @AppStorage defaults and plain UserDefaults reads in sync.
        UserDefaults.standard.register(defaults: [
            SettingsKey.teamsOnly: true,
            SettingsKey.onlyOnAC: false,
            SettingsKey.pulseMethod: PulseMethod.auto.rawValue,
            SettingsKey.pulseIntervalSeconds: 120,
            SettingsKey.pulseKey: PulseKey.f20.rawValue,
            SettingsKey.allowDisplaySleep: false,
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
            print("idle-before: \(idleBefore)s  idle-after: \(Self.idleSeconds())s")
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

        // Menu status line: Screen On/Off suffix (pure function seam; no singletons).
        store.mode = .on
        let modeOnText = store.stateText(now: at10)   // "Awake: On"
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: false) == "Awake: On",
              "status line unchanged: mode on + screen on")
        check(AppState.menuStatusText(modeOnText, paused: false, screenOff: true) == "Awake: On · Screen off",
              "status line suffix: mode on + screen off")
        store.mode = .off
        let modeOffText = store.stateText(now: at10)  // "Awake: Off"
        check(AppState.menuStatusText(modeOffText, paused: false, screenOff: true) == "Awake: Off · Screen off",
              "status line suffix: mode off + screen off")
        store.mode = .scheduled
        let scheduledText = store.stateText(now: at10)  // "Awake: On · until 18:00"
        check(AppState.menuStatusText(scheduledText, paused: false, screenOff: true) == "Awake: On · until 18:00 · Screen off",
              "status line suffix: scheduled active + screen off")
        check(AppState.menuStatusText("Disabled · 5:00 left", paused: true, screenOff: true) == "Disabled · 5:00 left",
              "pause countdown untouched: screen off")
        check(AppState.menuStatusText("Disabled · 5:00 left", paused: true, screenOff: false) == "Disabled · 5:00 left",
              "pause countdown untouched: screen on")

        defaults.removePersistentDomain(forName: suite)
        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0
    }
}

