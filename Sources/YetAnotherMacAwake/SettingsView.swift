import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var store = ScheduleStore.shared
    @ObservedObject private var ax = AccessibilityMonitor.shared
    @AppStorage(SettingsKey.onlyOnAC) private var onlyOnAC = false
    @AppStorage(SettingsKey.teamsOnly) private var teamsOnly = true
    @AppStorage(SettingsKey.pulseMethod) private var pulseMethodRaw = PulseMethod.auto.rawValue
    @AppStorage(SettingsKey.pulseIntervalSeconds) private var pulseInterval = 120
    @AppStorage(SettingsKey.pulseKey) private var pulseKeyRaw = PulseKey.f20.rawValue
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SettingsKey.allowDisplaySleep) private var allowDisplaySleep = false
    @State private var syncingLaunchAtLogin = false
    @State private var selectedDays: Set<Int> = []
    @State private var templateStart = Date()
    @State private var templateEnd = Date()

    var body: some View {
        TabView {
            scheduleTab
                .tabItem { Label("Schedule", systemImage: "calendar") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 460)
        .onAppear {
            NSApp.activate()
            syncingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            syncingLaunchAtLogin = false
        }
        .onChange(of: launchAtLogin) { _, value in
            guard !syncingLaunchAtLogin else { return }
            do {
                if value {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Not bundled or unsigned (e.g. `swift run`); revert to real state.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Schedule

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Awake follows the enabled windows for each day.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDays.isEmpty ? "Select at least one day." : "Set the time window for the selected days:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    DatePicker("", selection: templateStartBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("–")
                    DatePicker("", selection: templateEndBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    Text(selectedDays.isEmpty ? "no days" : "\(selectedDays.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Dim + block hits instead of `.disabled`: toggling `isEnabled` on
            // DatePicker (NSViewRepresentable) re-enters layout and trips
            // "AttributeGraph: cycle detected" in SwiftUI.
            .opacity(selectedDays.isEmpty ? 0.5 : 1)
            .allowsHitTesting(!selectedDays.isEmpty)

            HStack(spacing: 8) {
                Text("Quick select:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                quickSelectButton("All", indices: Array(0...6))
                quickSelectButton("Weekdays", indices: Array(0...4))
                quickSelectButton("Weekend", indices: [5, 6])
                quickSelectButton("Clear", indices: [])
            }

            HStack(spacing: 6) {
                ForEach(Array(ScheduleStore.dayNames.enumerated()), id: \.offset) { index, name in
                    dayChip(index: index, name: name)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Individual times (optional — override the batch window per day; click the circle to enable or disable a day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(ScheduleStore.dayNames.enumerated()), id: \.offset) { index, name in
                        dayTimeRow(index: index, name: name)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Seed the edit group with enabled days so the shared template shows their window.
            selectedDays = Set(store.days.indices.filter { store.days[$0].enabled })
            reloadTemplate()
        }
    }

    /// Replace the edit group and align enabled state with it (keeps chips and selection in sync).
    private func quickSelectButton(_ label: String, indices: [Int]) -> some View {
        Button(label) {
            selectedDays = Set(indices)
            for i in store.days.indices {
                store.days[i].enabled = selectedDays.contains(i)
            }
            store.save()
            reloadTemplate()
        }
    }

    private func dayChip(index: Int, name: String) -> some View {
        let isOn = selectedDays.contains(index)
        return Button {
            if isOn {
                selectedDays.remove(index)
                store.days[index].enabled = false
            } else {
                selectedDays.insert(index)
                store.days[index].enabled = true
            }
            store.save()
            reloadTemplate()
        } label: {
            Text(String(name.prefix(3)))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.accentColor : Color.gray.opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Template times always reflect the first (earliest weekday) selected day.
    private func reloadTemplate() {
        guard let first = selectedDays.sorted().first else { return }
        templateStart = Self.dateFromMinutes(store.days[first].startMinutes)
        templateEnd = Self.dateFromMinutes(store.days[first].endMinutes)
    }

    private var templateStartBinding: Binding<Date> {
        Binding(
            get: { templateStart },
            set: { newValue in
                templateStart = newValue
                let minutes = Self.minutesFromDate(newValue)
                for index in selectedDays {
                    store.days[index].startMinutes = minutes
                }
                store.save()
            }
        )
    }

    private var templateEndBinding: Binding<Date> {
        Binding(
            get: { templateEnd },
            set: { newValue in
                templateEnd = newValue
                let minutes = Self.minutesFromDate(newValue)
                for index in selectedDays {
                    store.days[index].endMinutes = minutes
                }
                store.save()
            }
        )
    }
    private func dayTimeRow(index: Int, name: String) -> some View {
        let isEnabled = store.days[index].enabled
        return HStack(spacing: 8) {
            Button {
                store.days[index].enabled.toggle()
                if store.days[index].enabled {
                    selectedDays.insert(index)
                } else {
                    selectedDays.remove(index)
                }
                store.save()
            } label: {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isEnabled ? Color.green : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(isEnabled ? "Enabled — click to disable this day" : "Disabled — click to enable this day")
            HStack(spacing: 8) {
                Text(name)
                    .frame(width: 80, alignment: .leading)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                DatePicker("", selection: perDayStartBinding(index), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("–")
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                DatePicker("", selection: perDayEndBinding(index), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
            }
            .opacity(isEnabled ? 1 : 0.4)
            .allowsHitTesting(isEnabled)
        }
        .padding(.vertical, 2)
    }

    /// Per-day overrides: editing writes only to this day, so days can differ from the batch window.
    private func perDayStartBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { Self.dateFromMinutes(store.days[index].startMinutes) },
            set: {
                store.days[index].startMinutes = Self.minutesFromDate($0)
                store.save()
            }
        )
    }

    private func perDayEndBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { Self.dateFromMinutes(store.days[index].endMinutes) },
            set: {
                store.days[index].endMinutes = Self.minutesFromDate($0)
                store.save()
            }
        )
    }



    // MARK: - Behavior

    private var behaviorTab: some View {
        Form {
            Section("Activity pulse") {
                Toggle("Only pulse when Microsoft Teams is running", isOn: $teamsOnly)
                Picker("Method", selection: $pulseMethodRaw) {
                    ForEach(PulseMethod.allCases, id: \.self) { method in
                        Text(method.label).tag(method.rawValue)
                    }
                }
                Picker("Silent key", selection: $pulseKeyRaw) {
                    ForEach(PulseKey.allCases, id: \.self) { key in
                        Text(key.label).tag(key.rawValue)
                    }
                }
                .disabled(pulseMethodRaw != PulseMethod.auto.rawValue)
                Text("Silent key is sent when accessibility is granted. F13–F19 may be bound by Aerospace or macOS — F20 has no default action on any keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $pulseInterval, in: 30...600, step: 30) {
                    Text("Send activity every \(pulseInterval) seconds")
                }
                .onChange(of: pulseInterval) { _, _ in
                    AppState.shared.evaluate()
                }
                Text("Shorter keeps Teams Available more reliably. Default 120 s; 240 s matches Teams' ~5-minute Away threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sleep prevention") {
                Toggle("Allow display to sleep while awake", isOn: $allowDisplaySleep)
                    .onChange(of: allowDisplaySleep) { _, _ in
                        AppState.shared.evaluate()
                    }
                Text("The display sleeps on its normal timer while the system keeps running — even with the lid closed. Requires AC power (battery ignores the system assertion); the Teams activity pulse pauses so the screen can turn off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Prevent sleep only on AC power", isOn: $onlyOnAC)
                Text("On battery the display may sleep and Teams may go Away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Yet Another Mac Awake")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Keeps the screen awake — even during long coding-agent runs — and keeps you Available in Microsoft Teams during your scheduled windows.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Author:")
                        .foregroundStyle(.secondary)
                    Text("Abdul Munim")
                }
                Link("www.munim.net", destination: URL(string: "https://www.munim.net/")!)
                Link("x.com/munim", destination: URL(string: "https://x.com/munim")!)
            }
            .font(.callout)
            Spacer()
            Text("Requires macOS 14 or later")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// Bundle version, with a fallback for `swift run` (no Info.plist in the raw binary).
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Permissions

    private var permissionsTab: some View {
        Form {
            Section("Accessibility") {
                HStack(spacing: 8) {
                    Image(systemName: ax.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ax.isTrusted ? .green : .orange)
                    Text(ax.isTrusted
                         ? "Granted — Yet Another Mac Awake can send silent keep-awake key events."
                         : "Not granted — keep-awake falls back to a subtle mouse jiggle.")
                }
                if !ax.isTrusted {
                    Button("Grant Permission…") {
                        ax.requestAccess()
                    }
                    Text("Opens System Settings > Privacy & Security > Accessibility. Enable Yet Another Mac Awake there, the status updates live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Date helpers

    static func dateFromMinutes(_ minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }

    static func minutesFromDate(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
