import Foundation
import SwiftData

@Model
final class CoachWorkspace {
    var uuid: UUID = UUID()
    var profileJSON: String = ""
    var pluginsJSON: String = ""
    var automationJSON: String = ""
    var updatedAt: Date = Date()
    init() {}
}

@Model
final class CoachCheckIn {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var expiresAt: Date = Date()
    var sessionID: UUID?
    var dayID: UUID?
    var minutes: Int = 0
    var availableMinutes: Int?
    var difficulty: String = ""
    var timing: String = ""
    var note: String = ""
    var kind: String = "feedback"
    init(kind: String = "feedback", note: String = "", expiresAt: Date = .now) {
        self.kind = kind; self.note = note; self.expiresAt = expiresAt
    }
}

@Model
final class CoachActionRecord {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var kind: String = ""
    var payloadJSON: String = ""
    var state: String = "pending"
    var receipt: String = ""
    var operationID: UUID = UUID()
    var expiresAt: Date = Date().addingTimeInterval(3600)
    init(kind: String, payloadJSON: String) { self.kind = kind; self.payloadJSON = payloadJSON }
}

@Model
final class CoachTrainingLink {
    var uuid: UUID = UUID()
    var planID: UUID = UUID()
    var dayID: UUID = UUID()
    var eventID: String = ""
    var eventCalendarID: String = ""
    var eventVersion: String = ""
    var eventStart: Date?
    var eventLookupDates: [Date] = []
    var alarmID: UUID?
    var retiredAlarmIDs: [UUID] = []
    var desiredJSON: String = ""
    var calendarReceipt: String = ""
    var alarmReceipt: String = ""
    var error: String = ""
    var pending = true
    init(planID: UUID, dayID: UUID) { self.planID = planID; self.dayID = dayID }
}
