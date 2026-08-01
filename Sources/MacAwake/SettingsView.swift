import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = ScheduleStore.shared
    @AppStorage(SettingsKey.onlyOnAC) private var onlyOnAC = false
    @AppStorage(SettingsKey.teamsOnly) private var teamsOnly = true
    @AppStorage(SettingsKey.pulseMethod) private var pulseMethodRaw = PulseMethod.auto.rawValue

    var body: some View {
        TabView {
            scheduleTab
                .tabItem { Label("Schedule", systemImage: "calendar") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            NSApp.activate()
        }
    }

    // MARK: - Schedule

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Awake follows the enabled windows for each day.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(Array(ScheduleStore.dayNames.enumerated()), id: \.offset) { index, name in
                    dayRow(index: index, name: name)
                }
            }
        }
        .padding()
    }

    private func dayRow(index: Int, name: String) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding(index))
                .labelsHidden()
            Text(name)
                .frame(width: 80, alignment: .leading)
            DatePicker("", selection: startBinding(index), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Text("–")
            DatePicker("", selection: endBinding(index), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func enabledBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { store.days[index].enabled },
            set: {
                store.days[index].enabled = $0
                store.save()
            }
        )
    }

    private func startBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { Self.dateFromMinutes(store.days[index].startMinutes) },
            set: {
                store.days[index].startMinutes = Self.minutesFromDate($0)
                store.save()
            }
        )
    }

    private func endBinding(_ index: Int) -> Binding<Date> {
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
                Text("A pulse every 4 minutes keeps Teams Available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sleep prevention") {
                Toggle("Prevent sleep only on AC power", isOn: $onlyOnAC)
                Text("On battery the display may sleep and Teams may go Away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Purpose", value: "Keep the screen awake and stay Available in Teams")
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
