import Foundation
import SwiftData

/// A versioned value snapshot provides atomic multi-item maintenance without partial patches.
@Model final class PersonalKnowledgeWorkspace {
    var uuid: UUID = UUID()
    var payloadJSON: String = ""
    var updatedAt: Date = Date()
    init() {}
}
@Model final class ChatConversation {
    var uuid: UUID = UUID()
    var draft: String = ""
    var title: String = "新的对话"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(title: String = "新的对话") { self.title = title }
}
