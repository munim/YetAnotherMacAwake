import Foundation
import AppKit
import CoreGraphics
import Combine
import IOKit.pwr_mgt
import IOKit.ps

enum PulseMethod: String, CaseIterable {
    case auto = "auto"
    case jiggle = "jiggle"

    var label: String {
        switch self {
        case .auto: return "Auto (silent key when allowed, else jiggle)"
        case .jiggle: return "Always mouse jiggle"
        }
    }
}

/// Inert keys for the invisible activity pulse. F20 has no default action on
/// macOS and no physical key on standard keyboards, so neither macOS nor
/// Aerospace binds it. Any F-key can be made configurable-safe in Settings.
enum PulseKey: Int, CaseIterable {
    case f13 = 0x69
    case f14 = 0x6B
    case f15 = 0x71
    case f16 = 0x6A
    case f17 = 0x40
    case f18 = 0x4F
    case f19 = 0x50
    case f20 = 0x5A
    case none = -1

    var label: String {
        switch self {
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20 (recommended)"
        case .none: return "Mouse only"
        }
    }
}

enum SettingsKey {
    static let onlyOnAC = "settings.onlyOnAC"
    static let pulseApps = "settings.pulseApps"
    static let pulseMethod = "settings.pulseMethod"
    static let pulseIntervalSeconds = "settings.pulseIntervalSeconds"
    static let pulseKey = "settings.pulseKey"
    static let launchAtLogin = "settings.launchAtLogin"
    static let allowDisplaySleep = "settings.allowDisplaySleep"
    static let pulseWhenScreenOff = "settings.pulseWhenScreenOff"
}

/// Which assertions the engine should hold for a given combination of user
/// settings and power state. `.none` releases everything; `.screenAndSystem`
/// holds display + system assertions; `.systemOnly` lets the display sleep.
enum AssertionProfile {
    case none, screenAndSystem, systemOnly
}

/// Known messaging apps that can gate the activity pulse. Bundle IDs were
/// verified against the Mac App Store (Slack) and Homebrew cask definitions
/// (Discord, Zoom); Teams carries both the classic and new client IDs.
enum MessagingApp: String, CaseIterable {
    case teams = "teams"
    case slack = "slack"
    case discord = "discord"
    case zoom = "zoom"

    var label: String {
        switch self {
        case .teams: return "Teams"
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .zoom: return "Zoom"
        }
    }

    var bundleIDs: Set<String> {
        switch self {
        case .teams: return ["com.microsoft.teams", "com.microsoft.teams2"]
        case .slack: return ["com.tinyspeck.slackmacgap"]
        case .discord: return ["com.hnc.Discord"]
        case .zoom: return ["us.zoom.xos"]
        }
    }
}

/// The pulse-app selection, persisted as a comma-delimited string of raw values
/// so `@AppStorage` can hold it. Defaults to all known apps checked; an empty
/// selection pauses the pulse entirely.
struct PulseAppsSelection: RawRepresentable, Equatable {
    var apps: Set<MessagingApp> = []

    init(_ apps: Set<MessagingApp> = []) { self.apps = apps }

    init(rawValue: String) {
        apps = Set(rawValue.split(separator: ",")
            .map(String.init)
            .compactMap(MessagingApp.init(rawValue:)))
    }

    var rawValue: String {
        apps.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// The persisted selection from a defaults domain; empty when absent or corrupt.
    static func fromDefaults(_ defaults: UserDefaults) -> PulseAppsSelection {
        PulseAppsSelection(rawValue: defaults.string(forKey: SettingsKey.pulseApps) ?? "")
    }

    /// The screen-off pulse-paused conflict: the display may sleep, the pulse is
    /// app-gated (at least one app checked), and no override re-enables it.
    /// Shared by the menu status line and the Settings warning so the two can't drift.
    func presenceMayGoAway(screenOff: Bool, overrideEnabled: Bool) -> Bool {
        screenOff && !apps.isEmpty && !overrideEnabled
    }
}

/// Holds power assertions while active and periodically sends synthetic
/// user activity so messaging-app presence never flips to Away.
final class AwakeEngine {
    static let shared = AwakeEngine()

    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var holding = false
    /// Screen-off mode swaps which assertion types are held; remembered so a
    /// settings change while holding can re-assert with the new types.
    private var heldScreenOff = false
    private var active = false
    private let defaults = UserDefaults.standard
    /// Power state from the 30 s poll; feeds the status line's battery-drop suffix.
    @Published private(set) var onACPower = true

    private var pulseTimer: Timer?
    private var pulseIntervalSeconds: TimeInterval = 240

    private init() {
        // Poll power state; the old NSWorkspace power notification no longer exists.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.recheck()
        }
        schedulePulseTimer()
    }

    var isActive: Bool { active }

    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        recheck()
        if value {
            pulse()
        }
    }

    /// Reschedule the keep-awake pulse; fires one pulse immediately.
    func setPulseInterval(_ seconds: Int) {
        let clamped = Double(Swift.min(600, Swift.max(30, seconds)))
        guard clamped != pulseIntervalSeconds else { return }
        pulseIntervalSeconds = clamped
        schedulePulseTimer()
        pulse()
    }

    private func schedulePulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: pulseIntervalSeconds, repeats: true) { [weak self] _ in
            self?.pulse()
        }
    }

    /// Power state and AC-only rule may change anytime; assertions follow.
    /// Exposed so the UI can force an immediate refresh on settings changes.
    func recheck() {
        onACPower = isOnACPower()
        let profile = Self.assertionProfile(
            active: active,
            onlyOnAC: defaults.bool(forKey: SettingsKey.onlyOnAC),
            onACPower: onACPower,
            allowDisplaySleep: defaults.bool(forKey: SettingsKey.allowDisplaySleep)
        )
        let want = profile != .none
        let screenOff = profile == .systemOnly
        if want && !holding {
            holdAssertions(screenOff: screenOff)
        } else if want && holding && screenOff != heldScreenOff {
            releaseAssertions()
            holdAssertions(screenOff: screenOff)
        } else if !want && holding {
            releaseAssertions()
        }
    }

    /// Pure decision: which assertion profile the current state wants. The sole
    /// unit-test seam for sleep-prevention settings (power state + user config).
    static func assertionProfile(active: Bool, onlyOnAC: Bool,
                                 onACPower: Bool, allowDisplaySleep: Bool) -> AssertionProfile {
        guard active else { return .none }
        if onlyOnAC && !onACPower { return .none }
        return allowDisplaySleep ? .systemOnly : .screenAndSystem
    }

    /// Pure decision: should the pulse fire given the selected apps and the
    /// bundle IDs currently running. Fires only while at least one selected app
    /// runs (any-of matching); an empty selection never pulses.
    static func pulseGate(selected: Set<MessagingApp>, runningBundleIDs: Set<String>) -> Bool {
        selected.contains { !$0.bundleIDs.isDisjoint(with: runningBundleIDs) }
    }

    private func holdAssertions(screenOff: Bool) {
        let name = "YetAnotherMacAwake" as CFString
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        heldScreenOff = screenOff
        // Screen-off mode lets the display sleep on its normal timer, so no
        // display assertion is held. The system assertion becomes
        // PreventSystemSleep (what `caffeinate -s` uses): it survives a closed
        // lid while on AC power, and battery power ignores it.
        if !screenOff {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, level, name, &displayAssertion)
        }
        let systemType = screenOff
            ? kIOPMAssertionTypePreventSystemSleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        IOPMAssertionCreateWithName(systemType as CFString, level, name, &systemAssertion)
        holding = true
    }

    private func releaseAssertions() {
        if displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
        }
        if systemAssertion != 0 {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
        }
        holding = false
    }

    func pulse() {
        recheck()
        guard active else { return }
        let screenOff = defaults.bool(forKey: SettingsKey.allowDisplaySleep)
        let override = defaults.bool(forKey: SettingsKey.pulseWhenScreenOff)
        // Fake activity resets the idle timer and would keep the display from
        // ever sleeping, so screen-off mode pauses the pulse — unless the
        // override opts back in, trading display sleep for presence availability.
        if screenOff && !override {
            NSLog("YetAnotherMacAwake pulse skipped: screen off mode")
            return
        }
        // App gate: the pulse fires only while at least one selected app runs;
        // an empty selection pauses the pulse entirely (never fires). Re-evaluated
        // on every pulse, so launching/quitting an app applies next interval.
        let selection = PulseAppsSelection.fromDefaults(defaults)
        guard !selection.apps.isEmpty else {
            NSLog("YetAnotherMacAwake pulse skipped: no messaging app selected")
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if !Self.pulseGate(selected: selection.apps, runningBundleIDs: running) {
            NSLog("YetAnotherMacAwake pulse skipped: no selected messaging app running")
            return
        }
        // The override still respects the AC-only rule: on battery with the rule
        // on the awake state is dropped entirely, so a pulse would fight it.
        if screenOff && override && defaults.bool(forKey: SettingsKey.onlyOnAC) && !onACPower {
            NSLog("YetAnotherMacAwake pulse skipped: on battery, sleep allowed")
            return
        }
        let method = PulseMethod(rawValue: defaults.string(forKey: SettingsKey.pulseMethod) ?? "") ?? .auto
        switch method {
        case .jiggle:
            jiggleMouse()
            NSLog("YetAnotherMacAwake pulse: mouse jiggle")
        case .auto:
            if AccessibilityMonitor.shared.isTrusted {
                if pressPulseKey() {
                    NSLog("YetAnotherMacAwake pulse: silent key")
                } else {
                    jiggleMouse()
                    NSLog("YetAnotherMacAwake pulse: mouse jiggle (silent key set to none)")
                }
            } else {
                jiggleMouse()
                NSLog("YetAnotherMacAwake pulse: mouse jiggle (grant accessibility for silent key)")
            }
        }
        if screenOff && override {
            NSLog("YetAnotherMacAwake pulse: screen off override")
        }
    }

    /// Press the configured inert key (F20 by default). No app maps it, so
    /// it resets idle time without visible side effects.
    @discardableResult
    private func pressPulseKey() -> Bool {
        let raw = defaults.integer(forKey: SettingsKey.pulseKey)
        guard let key = PulseKey(rawValue: raw), key != .none else { return false }
        press(key: CGKeyCode(key.rawValue))
        return true
    }

    private func press(key: CGKeyCode) {
        CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// Current cursor position in CG coordinates (origin top-left of primary
    /// display). Real position is mandatory: posting to `.zero` teleports the
    /// cursor when delta fields are ignored.
    private func currentMousePosition() -> CGPoint {
        let ns = NSEvent.mouseLocation
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first
        let height = primary?.frame.height ?? 0
        return CGPoint(x: ns.x, y: height - ns.y)
    }

    /// Absolute 1px move out and back. No delta fields: the position field is
    /// always a real location, so the cursor can never be teleported.
    private func jiggleMouse() {
        let base = currentMousePosition()
        postMouseMove(to: CGPoint(x: base.x + 1, y: base.y))
        postMouseMove(to: base)
    }

    private func postMouseMove(to point: CGPoint) {
        CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info) else {
            return true
        }
        return (source.takeRetainedValue() as String) == kIOPMACPowerKey
    }
}
