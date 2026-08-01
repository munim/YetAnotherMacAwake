import Foundation
import AppKit
import CoreGraphics
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
    static let teamsOnly = "settings.teamsOnly"
    static let pulseMethod = "settings.pulseMethod"
    static let pulseIntervalSeconds = "settings.pulseIntervalSeconds"
    static let pulseKey = "settings.pulseKey"
    static let launchAtLogin = "settings.launchAtLogin"
}

/// Holds power assertions while active and periodically sends synthetic
/// user activity so Teams never flips to Away.
final class AwakeEngine {
    static let shared = AwakeEngine()

    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var holding = false
    private var active = false
    private let defaults = UserDefaults.standard

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
    private func recheck() {
        let want = active && shouldHoldAssertions()
        if want && !holding {
            holdAssertions()
        } else if !want && holding {
            releaseAssertions()
        }
    }

    private func shouldHoldAssertions() -> Bool {
        if defaults.bool(forKey: SettingsKey.onlyOnAC) && !isOnACPower() {
            return false
        }
        return true
    }

    private func holdAssertions() {
        let name = "MacAwake" as CFString
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, level, name, &displayAssertion)
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, level, name, &systemAssertion)
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
        if defaults.bool(forKey: SettingsKey.teamsOnly) && !TeamsDetection.isTeamsRunning() {
            NSLog("MacAwake pulse skipped: Teams not running")
            return
        }
        let method = PulseMethod(rawValue: defaults.string(forKey: SettingsKey.pulseMethod) ?? "") ?? .auto
        switch method {
        case .jiggle:
            jiggleMouse()
            NSLog("MacAwake pulse: mouse jiggle")
        case .auto:
            if AccessibilityMonitor.shared.isTrusted {
                if pressPulseKey() {
                    NSLog("MacAwake pulse: silent key")
                } else {
                    jiggleMouse()
                    NSLog("MacAwake pulse: mouse jiggle (silent key set to none)")
                }
            } else {
                jiggleMouse()
                NSLog("MacAwake pulse: mouse jiggle (grant accessibility for silent key)")
            }
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

enum TeamsDetection {
    static func isTeamsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return id == "com.microsoft.teams" || id == "com.microsoft.teams2"
        }
    }
}
