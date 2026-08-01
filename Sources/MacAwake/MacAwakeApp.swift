import SwiftUI

@main
struct MacAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Text("Awake: Off")
            Divider()
            Button("Quit MacAwake") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "flame")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--force-on") {
            AwakeEngine.shared.setActive(true)
        }
    }
}
