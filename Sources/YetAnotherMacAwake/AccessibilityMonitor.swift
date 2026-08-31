import Foundation
import AppKit
import ApplicationServices
import Combine

/// Polls accessibility trust state; posts status changes live so the
/// settings window and engine react without relaunch.
final class AccessibilityMonitor: ObservableObject {
    static let shared = AccessibilityMonitor()

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()
    private var timer: Timer?

    private init() {}

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            NSLog("YetAnotherMacAwake accessibility: isTrusted=\(trusted)")
        }
    }

    /// Force a re-check after the user toggles in System Settings (poll is 2s but manual is instant).
    func recheckNow() {
        refresh()
    }

    /// Shows the system prompt and opens the Accessibility pane.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
