import Foundation

enum Posture: String, Codable, CaseIterable, Identifiable {
    case sitting, standing
    var id: String { rawValue }
    var title: String { self == .sitting ? "坐着" : "站着" }
    var symbol: String { self == .sitting ? "chair.fill" : "figure.stand" }
    var opposite: Posture { self == .sitting ? .standing : .sitting }
    var confirmation: String { self == .sitting ? "我已站起来" : "我已坐下" }
}

struct SchedulePeriod: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Int
    var end: Int
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

struct Settings: Codable, Equatable {
    var sittingMinutes = 30
    var standingMinutes = 15
    var snoozeMinutes = 5
    var soundEnabled = false
    var scheduleEnabled = false
    var weekdaysOnly = true
    var periods = [SchedulePeriod(start: 570, end: 720), SchedulePeriod(start: 840, end: 1080)]

    var scheduleError: String? {
        guard periods.count <= 12 else { return "最多支持 12 个时段。" }
        guard !periods.isEmpty else { return "请至少添加一个时段。" }
        let sorted = periods.sorted { $0.start < $1.start }
        for (index, period) in sorted.enumerated() {
            guard (0..<1440).contains(period.start), (0..<1440).contains(period.end), period.start < period.end else {
                return "开始时间必须早于结束时间，时段不能跨午夜。"
            }
            if index > 0, sorted[index - 1].end > period.start { return "时段不能重叠，请调整时间。" }
        }
        return nil
    }

    func duration(for posture: Posture) -> TimeInterval {
        TimeInterval(min(240, max(1, posture == .sitting ? sittingMinutes : standingMinutes)) * 60)
    }

    func activeSlot(at now: Date, calendar: Calendar = .current) -> ScheduleSlot? {
        guard scheduleEnabled, scheduleError == nil else { return nil }
        let weekday = calendar.component(.weekday, from: now)
        guard !weekdaysOnly || (2...6).contains(weekday) else { return nil }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard let period = periods.first(where: { $0.start <= minutes && minutes < $0.end }),
              let end = calendar.date(bySettingHour: period.end / 60, minute: period.end % 60, second: 0, of: now) else { return nil }
        return ScheduleSlot(key: "\(DayTotal.key(now, calendar: calendar))_\(period.id)", end: end)
    }
}

struct ScheduleSlot {
    var key: String
    var end: Date
}

struct Session: Codable {
    var posture: Posture
    var deadline: Date
    var scheduleKey: String?
    var scheduleEnd: Date?
}

struct DayTotal: Codable, Equatable {
    var sitting: TimeInterval = 0
    var standing: TimeInterval = 0

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func formatted(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    static func accumulate(from start: Date, to end: Date, posture: Posture,
                           into totals: inout [String: DayTotal], calendar: Calendar = .current) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else { break }
            let until = min(nextDay, end)
            let seconds = until.timeIntervalSince(cursor)
            let key = key(cursor, calendar: calendar)
            var total = totals[key] ?? DayTotal()
            if posture == .sitting { total.sitting += seconds } else { total.standing += seconds }
            totals[key] = total
            cursor = until
        }
    }
}

struct SavedState: Codable {
    var settings = Settings()
    var session: Session?
    var selectedPosture: Posture = .sitting
    var totals: [String: DayTotal] = [:]
    var suppressedSlots: Set<String> = []
}
