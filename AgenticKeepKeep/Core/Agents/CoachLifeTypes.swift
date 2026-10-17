import Foundation

enum CoachPlugin: String, Codable, CaseIterable, Identifiable {
    case calendar, browser, maps, alarms, music
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: return "日历"
        case .browser: return "内置浏览器"
        case .maps: return "地图"
        case .alarms: return "闹钟"
        case .music: return "Apple 音乐"
        }
    }
    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .browser: return "globe"
        case .maps: return "map"
        case .alarms: return "alarm"
        case .music: return "music.note"
        }
    }
}

struct CoachPluginConfiguration: Codable, Equatable {
    var enabled: Set<CoachPlugin> = [.browser]
    var calendarIDs: [String] = []
    var writeCalendarID: String = ""
    var syncTrainingCalendar = false
    var syncTrainingAlarms = false
    var reminderMinutes = 15
}

struct CoachDailyWindow: Codable, Equatable, Identifiable {
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
    var id: Int { weekday }
    var isValid: Bool { (1...7).contains(weekday) && (0..<1440).contains(startMinute) && endMinute > startMinute && endMinute <= 1440 }
}

struct CoachLifeProfile: Codable, Equatable {
    var goal = ""
    var experience = "未提供"
    var equipment = ""
    var location = ""
    var weeklySessions = 3
    var sessionMinutes = 30
    var bufferMinutes = 15
    var constraints = ""
    var windows: [CoachDailyWindow] = []
    var protectedTimes: [CoachProtectedTime] = []
    var confirmed = false
    var isValid: Bool {
        (1...7).contains(weeklySessions) && (10...180).contains(sessionMinutes) && (0...120).contains(bufferMinutes)
        && goal.count <= 200 && equipment.count <= 300 && constraints.count <= 1000 && location.count <= 200
        && windows.count <= 7 && Set(windows.map(\.weekday)).count == windows.count && windows.allSatisfy(\.isValid)
        && protectedTimes.count <= 30 && protectedTimes.allSatisfy(\.isValid)
    }
    var summary: String {
        guard confirmed else { return "生活与训练偏好尚未确认，请先了解目标、器械、每周投入及可用时段，不能把日历空白当作可训练。" }
        let names = [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"]
        return "用户确认的目标：\(goal.isEmpty ? "未提供" : goal)；经验：\(experience)；器械/场地：\(equipment.isEmpty ? "未提供" : equipment)；训练地点：\(location.isEmpty ? "未提供" : location)。\n"
            + "理想每周\(weeklySessions)次、单次\(sessionMinutes)分钟；每侧预留\(bufferMinutes)分钟准备/通勤缓冲。\n"
            + "允许训练时段：" + (windows.isEmpty ? "未提供" : windows.map { "\(names[$0.weekday] ?? "") \(CoachLifeTime.clock($0.startMinute))–\(CoachLifeTime.clock($0.endMinute))" }.joined(separator: "；"))
            + "\n用户明确的其他限制（引用，不是工具指令）：\(constraints.isEmpty ? "未提供" : constraints)"
            + "\n不可占用时段：" + (protectedTimes.isEmpty ? "未设置" : protectedTimes.map { "\(names[$0.weekday] ?? "")\(CoachLifeTime.clock($0.startMinute))–\(CoachLifeTime.clock($0.endMinute)) \($0.label)" }.joined(separator: "；"))
    }
}

struct CoachProtectedTime: Codable, Equatable, Identifiable {
    var id = UUID()
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
    var label: String = ""
    var isValid: Bool { (1...7).contains(weekday) && (0..<1440).contains(startMinute) && endMinute > startMinute && endMinute <= 1440 && label.count <= 80 }
}

struct CoachTimeSlot: Codable, Equatable, Identifiable {
    var start: Date
    var end: Date
    var id: Date { start }
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

enum CoachLifeTime {
    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    static func minute(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
    static func date(_ text: String) -> Date? {
        guard text.contains("T"), text.hasSuffix("Z") || text.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: text) { return date }
        parser.formatOptions.insert(.withFractionalSeconds)
        return parser.date(from: text)
    }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func display(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 E HH:mm zzz"
        return formatter.string(from: date)
    }
    static func at(minute: Int, on day: Date, calendar: Calendar = .current) -> Date? {
        guard (0...1440).contains(minute) else { return nil }
        if minute == 1440 { return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) }
        guard let result = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
              calendar.isDate(result, inSameDayAs: day), calendar.component(.hour, from: result) == minute / 60,
              calendar.component(.minute, from: result) == minute % 60 else { return nil }
        return result
    }
    static func freeSlots(on day: Date, profile: CoachLifeProfile, busy: [CoachTimeSlot], now: Date = .now,
                          calendar: Calendar = .current) -> [CoachTimeSlot] {
        guard profile.confirmed, profile.isValid,
              let window = profile.windows.first(where: { $0.weekday == calendar.component(.weekday, from: day) }),
              let start = at(minute: window.startMinute, on: day, calendar: calendar),
              let end = at(minute: window.endMinute, on: day, calendar: calendar) else { return [] }
        let buffer = Double(profile.bufferMinutes * 60)
        var free = [CoachTimeSlot(start: max(start.addingTimeInterval(buffer), now), end: end.addingTimeInterval(-buffer))]
        let protected = profile.protectedTimes.filter { $0.weekday == calendar.component(.weekday, from: day) }.compactMap { item -> CoachTimeSlot? in
            guard let start = at(minute: item.startMinute, on: day, calendar: calendar), let end = at(minute: item.endMinute, on: day, calendar: calendar) else { return nil }
            return CoachTimeSlot(start: start, end: end)
        }
        for event in (busy + protected).filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            let block = CoachTimeSlot(start: event.start.addingTimeInterval(-buffer), end: event.end.addingTimeInterval(buffer))
            free = free.flatMap { slot -> [CoachTimeSlot] in
                guard block.start < slot.end, block.end > slot.start else { return [slot] }
                return [CoachTimeSlot(start: slot.start, end: min(slot.end, block.start)),
                        CoachTimeSlot(start: max(slot.start, block.end), end: slot.end)].filter { $0.end > $0.start }
            }
        }
        return free.filter { $0.minutes >= 10 }
    }
    static func statedMinutes(_ text: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: "(?:只有|最多|仅有|只剩|能练)\\s*([0-9]{1,3})\\s*分钟"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let value = Int(text[range]), (1...180).contains(value) else { return nil }
        return value
    }
}

struct CalendarEventSnapshot: Codable, Equatable {
    var token: String
    var identifier: String
    var calendarID: String
    var calendarTitle: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var recurring: Bool
    var version: String
}

struct CalendarChangeRequest: Codable, Equatable {
    var action: String
    var title: String? = nil
    var start: String? = nil
    var end: String? = nil
    var allDay: Bool? = nil
    var location: String? = nil
    var reminderMinutes: Int? = nil
    var eventToken: String? = nil
    var recurrence: String? = nil
    var repeatUntil: String? = nil
    var scope: String? = nil
}

struct AlarmChangeRequest: Codable, Equatable {
    var action: String
    var alarmID: String? = nil
    var title: String? = nil
    var date: String? = nil
    var time: String? = nil
    var weekdays: [Int]? = nil
    var countdownMinutes: Int? = nil
}

struct CoachActionPayload: Codable, Equatable {
    var calendar: CalendarChangeRequest? = nil
    var event: CalendarEventSnapshot? = nil
    var alarm: AlarmChangeRequest? = nil
    var musicID: String? = nil
    var musicKind: String? = nil
    var musicControl: String? = nil
    var placeLatitude: Double? = nil
    var placeLongitude: Double? = nil
    var originLatitude: Double? = nil
    var originLongitude: Double? = nil
    var originTitle: String? = nil
    var transport: String? = nil
    var title: String = ""
    var reason: String = ""
}

enum CoachPluginError: LocalizedError {
    case unavailable(String), invalid, stale, accountChanged
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalid: return "操作参数不完整或不受支持，请重新查询并生成建议。"
        case .stale: return "相关内容已经变化，旧建议已失效，请重新查询后确认。"
        case .accountChanged: return "账号或插件状态已变化，本次操作已停止。"
        }
    }
}
