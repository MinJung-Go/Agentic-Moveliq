import Foundation
import SwiftData

/// A view-scoped generation gate prevents late writes after clear/dismiss/new requests.
@MainActor
final class CoachMemoryStore: ObservableObject {
    private(set) var generation = UUID()
    func begin() -> UUID { generation = UUID(); return generation }
    func invalidate() { generation = UUID() }

    static func ordered(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted { $0.date == $1.date ? $0.uuid.uuidString < $1.uuid.uuidString : $0.date < $1.date }
    }

    private static func anchor(in messages: [ChatMessage]) -> ChatMessage? {
        ordered(messages).first {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.pendingPlanJSON != nil || $0.pendingAdjustmentJSON != nil
        }
    }

    func load(_ messages: [ChatMessage]) -> CoachMemory? {
        guard let json = Self.anchor(in: messages)?.coachMemoryJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoachMemory.self, from: data)
    }

    func save(_ memory: CoachMemory, generation expected: UUID, context: ModelContext) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        guard let source = messages.first(where: { $0.uuid == memory.sessionID }) else { throw CancellationError() }
        let ordered = Self.ordered(messages.filter { $0.conversationID == source.conversationID })
        guard let anchor = Self.anchor(in: ordered), anchor.uuid == memory.sessionID,
              memory.isValid(for: CoachHistoryBuilder.turns(ordered)) else { throw CancellationError() }
        let previous = anchor.coachMemoryJSON
        anchor.coachMemoryJSON = String(decoding: try JSONEncoder().encode(memory), as: UTF8.self)
        do { try context.save() } catch { anchor.coachMemoryJSON = previous; throw error }
    }

    func clear(context: ModelContext) throws {
        invalidate()
        for message in try context.fetch(FetchDescriptor<ChatMessage>()) { context.delete(message) }
        try context.save()
    }
}

@MainActor
enum CoachHistoryBuilder {
    static func turns(_ messages: [ChatMessage]) -> [CoachTurn] {
        CoachMemoryStore.ordered(messages).compactMap { message in
            var content = message.content
            if let json = message.pendingPlanJSON {
                let status = message.planAcceptedAt != nil ? "已确认加入课程表（历史快照）" :
                    (message.planDecisionRaw == "rejected" ? "用户未采用" : "待用户确认，尚未执行")
                let date = message.planAcceptedAt ?? message.date
                content += "\n[计划：\(status)；dayOffset 相对 \(day(date))]\n\(json)"
            }
            if let json = message.pendingAdjustmentJSON {
                let status = message.adjustmentDecisionRaw == "applied" ? "已确认应用（历史快照）" : (message.adjustmentDecisionRaw == "rejected" ? "用户未采用" : "待用户确认，尚未执行")
                content += "\n[调整建议：\(status)；dayOffset 相对 \(day(message.adjustmentAppliedAt ?? message.date))]\n\(json)"
            }
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return CoachTurn(role: message.role, content: content, id: message.uuid, date: message.date)
        }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
