import SwiftUI

@main
struct MacAwakeApp: App {
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
        Text(state.stateText)

        Divider()

        Button { state.setMode(.on) } label: {
            Label("Always On", systemImage: state.store.mode == .on ? "checkmark" : "")
        }
        Button { state.setMode(.off) } label: {
            Label("Off", systemImage: state.store.mode == .off ? "checkmark" : "")
        }
        Button { state.setMode(.scheduled) } label: {
            Label("Follow Schedule", systemImage: state.store.mode == .scheduled ? "checkmark" : "")
        }

        Divider()

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit MacAwake") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            exit(Self.runSelfTest() ? 0 : 1)
        }
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
        AccessibilityMonitor.shared.start()
        if CommandLine.arguments.contains("--force-on") {
            AppState.shared.engine.setActive(true)
        }
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

        defaults.removePersistentDomain(forName: suite)
        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0
    }
}

