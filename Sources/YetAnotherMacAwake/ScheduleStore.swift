import Foundation
import Combine

enum Mode: String {
    case off = "off"
    case on = "on"
    case scheduled = "scheduled"
}

struct DaySchedule: Codable {
    var enabled = false
    var startMinutes = 9 * 60
    var endMinutes = 18 * 60
}

/// Per-day keep-awake windows, persisted in UserDefaults.
/// `days[0]` = Monday ... `days[6]` = Sunday.
final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()

    static let dayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    @Published var mode: Mode = .scheduled
    @Published var days: [DaySchedule] = Array(repeating: DaySchedule(), count: 7)
    /// Persisted "Always On" timer: while `mode == .on` and `onExpiresAt` is set,
    /// the engine stays on until that instant, then transitions to `.scheduled`.
    /// `onDurationMinutes` is the chosen duration, kept for menu checkmarks.
    @Published var onExpiresAt: Date?
    @Published var onDurationMinutes: Int?

    private let defaults: UserDefaults
    private static let modeKey = "schedule.mode"
    private static let daysKey = "schedule.days"
    private static let onExpiresKey = "schedule.onExpiresAt"
    private static let onDurationKey = "schedule.onDurationMinutes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.modeKey), let m = Mode(rawValue: raw) {
            mode = m
        }
        onExpiresAt = defaults.object(forKey: Self.onExpiresKey) as? Date
        onDurationMinutes = defaults.object(forKey: Self.onDurationKey) as? Int
        if let data = defaults.data(forKey: Self.daysKey),
           let decoded = try? JSONDecoder().decode([DaySchedule].self, from: data),
           decoded.count == 7 {
            days = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: Self.daysKey)
        }
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        if let expires = onExpiresAt {
            defaults.set(expires, forKey: Self.onExpiresKey)
        } else {
            defaults.removeObject(forKey: Self.onExpiresKey)
        }
        if let duration = onDurationMinutes {
            defaults.set(duration, forKey: Self.onDurationKey)
        } else {
            defaults.removeObject(forKey: Self.onDurationKey)
        }
    }

    func activeNow(now: Date = Date()) -> Bool {
        switch mode {
        case .off:
            return false
        case .on:
            return true
        case .scheduled:
            let day = days[dayIndex(for: now)]
            return day.enabled && inWindow(day, now: now)
        }
    }

    func inWindow(_ day: DaySchedule, now: Date) -> Bool {
        let m = minutesOfDay(now)
        if day.startMinutes < day.endMinutes {
            return m >= day.startMinutes && m < day.endMinutes
        } else if day.startMinutes > day.endMinutes {
            // Overnight window, e.g. 22:00 -> 02:00
            return m >= day.startMinutes || m < day.endMinutes
        }
        return false
    }

    func dayIndex(for date: Date) -> Int {
        // Calendar weekday: 1 = Sunday ... 7 = Saturday
        let wd = Calendar.current.component(.weekday, from: date)
        return (wd + 5) % 7
    }

    func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Next schedule start/end boundary at or after `now`.
    func nextBoundary(now: Date = Date()) -> Date? {
        let cal = Calendar.current
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for event in events(for: dayIndex(for: day), on: day) where event > now {
                return event
            }
        }
        return nil
    }

    private func events(for dayIndex: Int, on date: Date) -> [Date] {
        let day = days[dayIndex]
        guard day.enabled else { return [] }
        let cal = Calendar.current
        var start = cal.dateComponents([.year, .month, .day], from: date)
        start.hour = day.startMinutes / 60
        start.minute = day.startMinutes % 60
        start.second = 0
        var end = start
        end.hour = day.endMinutes / 60
        end.minute = day.endMinutes % 60
        var out: [Date] = []
        if let s = cal.date(from: start) { out.append(s) }
        if let e = cal.date(from: end) { out.append(e) }
        return out.sorted()
    }

    func stateText(now: Date = Date()) -> String {
        switch mode {
        case .off:
            return "Awake: Off"
        case .on:
            if let text = Self.remainingText(until: onExpiresAt, now: now) {
                return "Awake: On · \(text) left"
            }
            return "Awake: On"
        case .scheduled:
            if activeNow(now: now) {
                if let boundary = nextBoundary(now: now) {
                    return "Awake: On · until \(Self.timeString(boundary))"
                }
                return "Awake: On"
            }
            if let boundary = nextBoundary(now: now) {
                return "Awake: Off · starts \(Self.timeString(boundary))"
            }
            return "Awake: Off · no windows"
        }
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Clear the Always-On timer (used when leaving `.on` mode or on expiry).
    func clearOnTimer() {
        onExpiresAt = nil
        onDurationMinutes = nil
        save()
    }

    /// The mode "Always On" should move to when its timer expires, or nil if it
    /// should keep running. Pure seam for the expiry decision.
    static func onTimerTarget(mode: Mode, expiresAt: Date?, now: Date) -> Mode? {
        guard mode == .on, let expiresAt, expiresAt <= now else { return nil }
        return .scheduled
    }

    /// Human-readable remaining Always-On time, or nil when no timer is armed or
    /// it has already expired (so the UI never shows a stale "0m left").
    static func remainingText(until: Date?, now: Date) -> String? {
        guard let until else { return nil }
        let remaining = until.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let totalMinutes = Int(ceil(remaining / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
