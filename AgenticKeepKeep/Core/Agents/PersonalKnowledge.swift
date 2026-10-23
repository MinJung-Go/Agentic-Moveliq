import Foundation

// Pure values: neither model output nor imported text grants business-tool permissions.
enum KnowledgeKind: String, Codable, CaseIterable { case skill, profile, memory
    var title: String { switch self { case .skill: return "技能"; case .profile: return "资料"; case .memory: return "记忆" } }
}
enum KnowledgeStatus: String, Codable { case active, disabled, archived }
enum KnowledgeEvidenceKind: String, Codable {
    case suggestion, explicitRequest, preference, endorsement, feedback, execution
    var title: String {
        switch self {
        case .suggestion: return "助手建议，尚未验证"
        case .explicitRequest: return "你要求保存，效果未验证"
        case .preference: return "你表达的资料或偏好"
        case .endorsement: return "你认可的方法"
        case .feedback: return "你反馈的个人体验"
        case .execution: return "应用操作已完成，不代表训练效果"
        }
    }
}
struct KnowledgeSource: Codable, Equatable, Identifiable {
    var id: UUID
    var conversationID: UUID
    var role: String
    var text: String
    var date: Date
    var operationCompleted: Bool = false
}
struct KnowledgeEvidence: Codable, Equatable, Identifiable {
    var id: UUID
    var conversationID: UUID
    var kind: KnowledgeEvidenceKind
    var date: Date
    var sourceDeleted: Bool = false
    // Do not keep a second copy of the conversation; open the source message while it exists.
}
struct KnowledgeContent: Codable, Equatable {
    var name: String
    var description: String
    var body: String
    var profileField: PersonalProfileField? = nil
}
/// Stable field contract shared by tools, management, context and USER.md export.
enum PersonalProfileField: String, Codable, CaseIterable, Identifiable {
    case name, nickname, timezone, background, preferences
    var id: String { rawValue }
    var title: String {
        switch self { case .name: return "姓名"; case .nickname: return "称呼"; case .timezone: return "时区"; case .background: return "关于我"; case .preferences: return "我的偏好" }
    }
    static func legacy(_ name: String) -> Self? {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "姓名", "name": return .name
        case "称呼", "昵称", "nickname": return .nickname
        case "时区", "timezone": return .timezone
        case "背景", "关于我", "background": return .background
        case "偏好", "我的偏好", "回答偏好", "表达偏好", "沟通偏好", "preferences": return .preferences
        default: return nil
        }
    }
    /// Only unambiguous exact legacy labels migrate; bodies, IDs and history stay untouched.
    static func migrating(_ original: KnowledgeState) -> KnowledgeState {
        var state = original
        for field in allCases {
            let matches = state.items.indices.filter {
                let item = state.items[$0]
                return item.kind == .profile && !item.candidate &&
                    (item.content.profileField == field || (item.content.profileField == nil && legacy(item.content.name) == field))
            }
            if matches.count == 1, let index = matches.first,
               field != .timezone || TimeZone(identifier: state.items[index].content.body.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                state.items[index].content.profileField = field
            }
        }
        return state
    }
    static func markdown(_ items: [KnowledgeItem]) -> String {
        var sections: [String] = []
        for field in allCases {
            let matches = items.filter { $0.content.profileField == field }
            if !matches.isEmpty { sections.append("## " + field.title + "\n" + matches.map { $0.content.body }.joined(separator: "\n\n")) }
        }
        let others = items.filter { $0.content.profileField == nil }
        if !others.isEmpty { sections.append("## 其他已保存资料\n" + others.map { "### " + $0.content.name + "\n" + $0.content.body }.joined(separator: "\n\n")) }
        return sections.joined(separator: "\n\n")
    }
}
struct KnowledgePatch: Codable, Equatable {
    enum Field: String, Codable { case name, description, body }
    var field: Field
    var oldString: String
    var newString: String
    enum CodingKeys: String, CodingKey { case field; case oldString = "old_string"; case newString = "new_string" }
}
struct KnowledgeRevision: Codable, Equatable, Identifiable {
    var id: UUID
    var version: Int
    var before: KnowledgeContent
    var after: KnowledgeContent
    var patches: [KnowledgePatch]
    var date: Date
    var reason: String
}
struct KnowledgeItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: KnowledgeKind
    var content: KnowledgeContent
    var revision = 1
    var status: KnowledgeStatus = .active
    var candidate = false
    var evidence: [KnowledgeEvidence] = []
    var history: [KnowledgeRevision] = []
    var createdAt = Date()
    var updatedAt = Date()
    var expiresAt: Date?
    var available: Bool { !candidate && status == .active && (expiresAt == nil || expiresAt! > Date()) }
}
struct KnowledgeNotice: Codable, Equatable, Identifiable {
    var id = UUID()
    var itemID: UUID
    var conversationID: UUID?
    var message: String
    var revision: Int
    var previousContent: KnowledgeContent?
    var previousStatus: KnowledgeStatus?
    var previousCandidate: Bool?
    var date = Date()
    var undone = false
    // Optional for snapshots written before the dismiss action was introduced.
    var dismissed: Bool? = nil
}
struct KnowledgeOperation: Codable, Equatable {
    var id: String
    var payload: String
    var itemID: UUID
    var revision: Int
}
struct KnowledgeJob: Codable, Equatable, Identifiable {
    var id = UUID()
    var conversationID: UUID
    var sourceIDs: [UUID]
    var historical = false
    var completedReceiptIDs: [UUID] = []
    var state = "queued"
    var attempts = 0
    var error: String?
    var createdAt = Date()
}
struct KnowledgeState: Codable, Equatable {
    var enabledAt = Date()
    var items: [KnowledgeItem] = []
    var notices: [KnowledgeNotice] = []
    var operations: [KnowledgeOperation] = []
    var jobs: [KnowledgeJob] = []
    // Source identifiers only: deleted bodies and revisions are never retained here.
    var suppressedSources: [UUID] = []
    var activeConversationID: UUID?
}
enum KnowledgeError: LocalizedError {
    case invalid(String), conflict, ambiguous, duplicate(UUID), suppressed, missing
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .conflict: return "内容已有新的修改，请重新读取后再保存。"
        case .ambiguous: return "修改片段不存在或不唯一，请补充定位内容。"
        case .duplicate(let id): return "已有相似内容（\(id.uuidString)），请先读取，再局部修改或补充来源。"
        case .suppressed: return "这段来源已撤销或删除，不会再次自动保存。"
        case .missing: return "内容已删除或不可用。"
        }
    }
}

enum KnowledgeRules {
    static let maxItems = 1000
    static let maxBodyBytes = 6000
    static func validate(_ content: KnowledgeContent, kind: KnowledgeKind) throws {
        guard !content.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.name.count <= 80, !content.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.description.count <= 240,
              !content.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.body.utf8.count <= maxBodyBytes else {
            throw KnowledgeError.invalid("名称、简介和正文不能为空；名称最多 80 字，简介最多 240 字，正文最多 6 KB。")
        }
        if let field = content.profileField {
            guard kind == .profile else { throw KnowledgeError.invalid("仅个人资料可指定画像字段。") }
            if field == .timezone, TimeZone(identifier: content.body.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                throw KnowledgeError.invalid("时区应使用有效标识，例如 Asia/Shanghai。")
            }
        }
        let text = content.name + "\n" + content.description + "\n" + content.body
        let credentialPattern = #"(?i)(sk-[a-z0-9_-]{16,}|(?:password|passwd|api[_ -]?key|access[_ -]?token|密码|密钥)\s*[:=：]\s*\S{6,})"#
        guard text.range(of: credentialPattern, options: .regularExpression) == nil else {
            throw KnowledgeError.invalid("内容疑似包含密码或密钥，请移除后再保存。")
        }
        if kind == .skill {
            guard content.body.contains("## 适用"), content.body.contains("## 步骤"), content.body.contains("## 注意") else {
                throw KnowledgeError.invalid("技能需保留「## 适用」「## 步骤」「## 注意」三个章节。")
            }
        }
    }
    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    static func terms(_ text: String) -> Set<String> {
        let chars = Array(normalized(text))
        guard chars.count > 1 else { return Set(chars.map(String.init)) }
        return Set(zip(chars, chars.dropFirst()).map { String([$0, $1]) })
    }
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = terms(lhs), b = terms(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }
    static func search(_ query: String, in state: KnowledgeState, includeInactive: Bool = false, kind: KnowledgeKind = .skill) -> [KnowledgeItem] {
        let query = normalized(query)
        guard !query.isEmpty else { return [] }
        var ranked: [(item: KnowledgeItem, score: Double)] = []
        for item in state.items where item.kind == kind && (includeInactive || item.available) {
            let title = normalized(item.content.name)
            var score = title.contains(query) ? 3.0 : 0.0
            score += similarity(query, title) * 2.0
            score += similarity(query, item.content.description + item.content.body) * 0.5
            if score >= 0.35 { ranked.append((item, score)) }
        }
        ranked.sort {
            if $0.score == $1.score { return $0.item.id.uuidString < $1.item.id.uuidString }
            return $0.score > $1.score
        }
        return ranked.prefix(5).map { $0.item }
    }

    static func applying(_ patches: [KnowledgePatch], to original: KnowledgeContent, kind: KnowledgeKind) throws -> KnowledgeContent {
        guard !patches.isEmpty, patches.count <= 24 else { throw KnowledgeError.invalid("每次需要 1～24 个局部修改。") }
        var result = original
        for patch in patches {
            var field: String
            switch patch.field { case .name: field = result.name; case .description: field = result.description; case .body: field = result.body }
            guard !patch.oldString.isEmpty else { throw KnowledgeError.ambiguous }
            // Count overlapping occurrences as ambiguous too.
            var positions: [Range<String.Index>] = []
            var cursor = field.startIndex
            while cursor < field.endIndex, let range = field.range(of: patch.oldString, range: cursor..<field.endIndex) {
                positions.append(range); cursor = field.index(after: range.lowerBound)
            }
            guard positions.count == 1, let range = positions.first else { throw KnowledgeError.ambiguous }
            if kind == .skill && patch.field == .body && patch.oldString != patch.newString && patch.oldString == field {
                throw KnowledgeError.invalid("正文只能局部修改，请保留原有章节，分段编辑。")
            }
            field.replaceSubrange(range, with: patch.newString)
            switch patch.field { case .name: result.name = field; case .description: result.description = field; case .body: result.body = field }
        }
        try validate(result, kind: kind)
        return result
    }
    // Editor creates exact patches rather than sending the entire edited document as an update.
    static func diff(from old: KnowledgeContent, to new: KnowledgeContent) throws -> [KnowledgePatch] {
        var patches: [KnowledgePatch] = []
        if old.name != new.name { patches.append(.init(field: .name, oldString: old.name, newString: new.name)) }
        if old.description != new.description { patches.append(.init(field: .description, oldString: old.description, newString: new.description)) }
        if old.body != new.body {
            // Section edits keep headings as unique anchors, including inserts/deletions in empty sections.
            let oldParts = old.body.components(separatedBy: "\n## ")
            let newParts = new.body.components(separatedBy: "\n## ")
            if oldParts.count > 1 && oldParts.count == newParts.count {
                for (a, b) in zip(oldParts, newParts) where a != b {
                    patches.append(.init(field: .body, oldString: a, newString: b))
                }
            } else {
                let a = Array(old.body), b = Array(new.body)
                var prefix = 0, suffix = 0
                while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
                while suffix < min(a.count - prefix, b.count - prefix), a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
                var start = prefix, end = a.count - suffix
                if start == end { if start > 0 { start -= 1 } else if end < a.count { end += 1 } }
                while start > 0 || end < a.count {
                    let fragment = String(a[start..<end])
                    if !fragment.isEmpty && old.body.components(separatedBy: fragment).count == 2 { break }
                    if start > 0 { start -= 1 }; if end < a.count { end += 1 }
                }
                let replacement = String(a[start..<prefix]) + String(b[prefix..<(b.count - suffix)]) + String(a[(a.count - suffix)..<end])
                patches.append(.init(field: .body, oldString: String(a[start..<end]), newString: replacement))
            }
        }
        return patches
    }
    static func payload<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

extension KnowledgeState {
    @discardableResult mutating func applyVerified(_ proposal: KnowledgeProposal, evidence: [KnowledgeEvidence], operationID: String) throws -> UUID {
        let target = items.first { $0.id == proposal.skillID }
        if proposal.action != "save" {
            guard let target else { throw KnowledgeError.missing }
            if let kind = proposal.kind, target.kind != kind { throw KnowledgeError.invalid("目标类别不符。") }
        }
        let kind = proposal.action == "save" ? proposal.kind : target?.kind
        guard let kind else { throw KnowledgeError.invalid("缺少内容类别。") }
        if kind != .skill {
            guard evidence.contains(where: { [.preference, .explicitRequest, .endorsement, .feedback].contains($0.kind) }) else {
                throw KnowledgeError.invalid("个人资料与记忆需要用户来源，不能仅依据助手建议或执行回执。")
            }
        }
        switch proposal.action {
        case "save":
            guard let content = proposal.content else { throw KnowledgeError.invalid("缺少保存内容。") }
            return try save(kind: kind, content: content, evidence: evidence, expiresAt: proposal.expiresAt)
        case "patch":
            guard let id = proposal.skillID, let version = proposal.expectedRevision, let patches = proposal.patches else { throw KnowledgeError.invalid("缺少局部修改参数。") }
            try patch(id: id, expected: version, operationID: operationID, patches: patches, evidence: evidence)
            return id
        case "evidence":
            guard let id = proposal.skillID else { throw KnowledgeError.missing }
            try addEvidence(evidence, to: id)
            return id
        default: throw KnowledgeError.invalid("自动整理不支持此操作。")
        }
    }

    mutating func dismissNotice(_ id: UUID) {
        guard let index = notices.firstIndex(where: { $0.id == id }) else { return }
        notices[index].dismissed = true
    }

    mutating func save(kind: KnowledgeKind, content: KnowledgeContent, evidence: [KnowledgeEvidence], expiresAt: Date? = nil) throws -> UUID {
        var content = content
        if kind == .profile, content.profileField == nil { content.profileField = PersonalProfileField.legacy(content.name) }
        try KnowledgeRules.validate(content, kind: kind)
        guard !evidence.isEmpty else { throw KnowledgeError.invalid("保存需要可核验的来源。") }
        let hasFreshExplicit = evidence.contains { $0.kind == .explicitRequest && !suppressedSources.contains($0.id) }
        guard hasFreshExplicit || evidence.contains(where: { !suppressedSources.contains($0.id) }) else { throw KnowledgeError.suppressed }
        if let field = content.profileField,
           let existing = items.first(where: { $0.kind == .profile && ($0.content.profileField ?? PersonalProfileField.legacy($0.content.name)) == field }) {
            if existing.content.body == content.body { try addEvidence(evidence, to: existing.id); return existing.id }
            throw KnowledgeError.duplicate(existing.id)
        }
        if let same = items.first(where: { $0.kind == kind && $0.content == content }) {
            try addEvidence(evidence, to: same.id); return same.id
        }
        if let similar = items.first(where: { $0.kind == kind &&
            (KnowledgeRules.normalized($0.content.name) == KnowledgeRules.normalized(content.name)
             || KnowledgeRules.similarity($0.content.name, content.name) > 0.85) }) {
            throw KnowledgeError.duplicate(similar.id)
        }
        guard items.count < KnowledgeRules.maxItems else { throw KnowledgeError.invalid("知识库已达 1,000 条，请先整理或导出。") }
        var item = KnowledgeItem(kind: kind, content: content)
        item.evidence = evidence; item.expiresAt = expiresAt
        item.candidate = kind == .skill && !evidence.contains { $0.kind != .suggestion }
        if kind != .skill && evidence.allSatisfy({ $0.kind == .suggestion }) { throw KnowledgeError.invalid("助手建议不能成为个人事实。") }
        items.append(item)
        if !item.candidate { notices.append(.init(itemID: item.id, conversationID: evidence.last?.conversationID, message: "已记住 · " + content.name, revision: item.revision)) }
        return item.id
    }
    mutating func addEvidence(_ evidence: [KnowledgeEvidence], to id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw KnowledgeError.missing }
        for source in evidence where !suppressedSources.contains(source.id) {
            if let old = items[index].evidence.firstIndex(where: { $0.id == source.id }) {
                if items[index].evidence[old].kind == .suggestion { items[index].evidence[old] = source }
            } else { items[index].evidence.append(source) }
        }
        if items[index].candidate, items[index].status == .active, items[index].evidence.contains(where: { $0.kind != .suggestion && !suppressedSources.contains($0.id) }) {
            items[index].candidate = false; items[index].revision += 1; items[index].updatedAt = Date()
            notices.append(.init(itemID: id, conversationID: evidence.last?.conversationID, message: "已保存技能 · " + items[index].content.name, revision: items[index].revision, previousCandidate: true))
        }
    }
    mutating func patch(id: UUID, expected: Int, operationID: String, patches: [KnowledgePatch], evidence: [KnowledgeEvidence] = [], reason: String = "局部修改", manual: Bool = false) throws {
        struct Payload: Codable { var id: UUID; var version: Int; var patches: [KnowledgePatch]; var evidence: [KnowledgeEvidence] }
        let payload = try KnowledgeRules.payload(Payload(id: id, version: expected, patches: patches, evidence: evidence))
        guard !operationID.isEmpty, operationID.count <= 160 else { throw KnowledgeError.invalid("缺少有效的操作标识。") }
        if let done = operations.first(where: { $0.id == operationID }) {
            guard done.payload == payload else { throw KnowledgeError.invalid("操作标识已被其他修改使用。") }; return
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw KnowledgeError.missing }
        let before = items[index]
        guard before.revision == expected else { throw KnowledgeError.conflict }
        guard manual || before.status == .active else { throw KnowledgeError.invalid("已停用或归档，自动维护不能修改。") }
        guard manual || evidence.contains(where: { $0.kind != .suggestion && !suppressedSources.contains($0.id) }) else { throw KnowledgeError.invalid("修改已有内容需要用户证据或执行结果；含糊时请询问。") }
        let content = try KnowledgeRules.applying(patches, to: before.content, kind: before.kind)
        var next = self
        if content != before.content {
            next.items[index].content = content; next.items[index].revision += 1; next.items[index].updatedAt = Date()
            next.items[index].history.append(.init(id: UUID(), version: next.items[index].revision, before: before.content, after: content, patches: patches, date: Date(), reason: reason))
            if !before.candidate { next.notices.append(.init(itemID: id, conversationID: evidence.last?.conversationID, message: "已更新 · " + content.name, revision: next.items[index].revision, previousContent: before.content)) }
        }
        if !evidence.isEmpty { try next.addEvidence(evidence, to: id) }
        next.operations.append(.init(id: operationID, payload: payload, itemID: id, revision: next.items[index].revision))
        self = next
    }
    mutating func setStatus(_ status: KnowledgeStatus, id: UUID, expected: Int) throws {
        guard let i = items.firstIndex(where: { $0.id == id }) else { throw KnowledgeError.missing }
        guard items[i].revision == expected else { throw KnowledgeError.conflict }
        let previous = items[i].status
        guard previous != status else { return }
        items[i].status = status; items[i].revision += 1; items[i].updatedAt = Date()
        notices.append(.init(itemID: id, message: status == .active ? "已恢复 · \(items[i].content.name)" : "已停止自动使用 · \(items[i].content.name)", revision: items[i].revision, previousStatus: previous))
    }
    mutating func delete(id: UUID, expected: Int) throws {
        guard let item = items.first(where: { $0.id == id }) else { throw KnowledgeError.missing }
        guard item.revision == expected else { throw KnowledgeError.conflict }
        suppressedSources = Array(Set(suppressedSources + item.evidence.map(\.id)))
        items.removeAll { $0.id == id }; notices.removeAll { $0.itemID == id }; operations.removeAll { $0.itemID == id }
    }
    mutating func undo(noticeID: UUID) throws {
        guard let notice = notices.first(where: { $0.id == noticeID }), !notice.undone,
              let i = items.firstIndex(where: { $0.id == notice.itemID }) else { throw KnowledgeError.missing }
        guard items[i].revision == notice.revision else { throw KnowledgeError.conflict }
        suppressedSources = Array(Set(suppressedSources + items[i].evidence.map(\.id)))
        if let content = notice.previousContent {
            let before = items[i].content
            items[i].content = content; items[i].revision += 1
            items[i].history.append(.init(id: UUID(), version: items[i].revision, before: before, after: content, patches: [], date: Date(), reason: "撤销上次修改"))
        } else if let status = notice.previousStatus { items[i].status = status; items[i].revision += 1 }
        else if let candidate = notice.previousCandidate { items[i].candidate = candidate; items[i].revision += 1 }
        else { try delete(id: items[i].id, expected: items[i].revision); return }
        if let n = notices.firstIndex(where: { $0.id == noticeID }) { notices[n].undone = true }
    }
    mutating func removeConversation(_ id: UUID) {
        jobs.removeAll { $0.conversationID == id }
        for i in items.indices {
            for j in items[i].evidence.indices where items[i].evidence[j].conversationID == id { items[i].evidence[j].sourceDeleted = true }
        }
        let removedIDs = Set(items.filter { $0.candidate && $0.evidence.allSatisfy(\.sourceDeleted) }.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        notices.removeAll { removedIDs.contains($0.itemID) }
        operations.removeAll { removedIDs.contains($0.itemID) }
        for i in notices.indices where notices[i].conversationID == id { notices[i].conversationID = nil }
    }
}

struct KnowledgeArchive: Codable {
    var format = "moveliq.personal-knowledge"
    var version = 1
    var account: String
    var exportedAt = Date()
    var items: [KnowledgeItem]
    var userMarkdown: String
    var memoryMarkdown: String
    init(state: KnowledgeState, account: String) {
        self.account = account
        items = PersonalProfileField.migrating(state).items.filter { !$0.candidate }
        // Source IDs are opaque, but no source contents/conversation links travel to another device.
        for i in items.indices { for j in items[i].evidence.indices { items[i].evidence[j].sourceDeleted = true } }
        userMarkdown = PersonalProfileField.markdown(items.filter { $0.kind == .profile })
        memoryMarkdown = Self.markdown(items.filter { $0.kind == .memory })
    }
    static func markdown(_ items: [KnowledgeItem]) -> String { items.map { "## \($0.content.name)\n\($0.content.body)" }.joined(separator: "\n\n") }
    static func read(_ data: Data) throws -> Self {
        guard data.count <= 12_000_000 else { throw KnowledgeError.invalid("导入文件不能超过 12 MB。") }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.format == "moveliq.personal-knowledge", archive.version == 1,
              archive.items.count <= KnowledgeRules.maxItems, Set(archive.items.map(\.id)).count == archive.items.count else { throw KnowledgeError.invalid("文件格式、版本或条目数量不受支持。") }
        for item in archive.items {
            guard !item.candidate, item.revision > 0, item.history.count <= 1000, item.evidence.count <= 2000 else { throw KnowledgeError.invalid("归档条目无效。") }
            try KnowledgeRules.validate(item.content, kind: item.kind)
            for revision in item.history {
                try KnowledgeRules.validate(revision.before, kind: item.kind)
                try KnowledgeRules.validate(revision.after, kind: item.kind)
            }
        }
        return archive
    }
    private func sameContent(_ a: KnowledgeItem, _ b: KnowledgeItem) -> Bool {
        a.kind == b.kind && a.candidate == b.candidate && a.content == b.content && a.revision == b.revision && a.status == b.status && a.expiresAt == b.expiresAt
    }
    func conflicts(in state: KnowledgeState) -> [KnowledgeItem] {
        items.filter { incoming in state.items.contains { $0.id == incoming.id && !sameContent($0, incoming) } }
    }
    func applying(to state: KnowledgeState, replaceIDs: Set<UUID>) throws -> KnowledgeState {
        var next = state
        for var incoming in items {
            for i in incoming.evidence.indices { incoming.evidence[i].sourceDeleted = true }
            if let i = next.items.firstIndex(where: { $0.id == incoming.id }) {
                guard replaceIDs.contains(incoming.id), !sameContent(next.items[i], incoming) else { continue }
                // Explicit restore is separate from Agent patch; invalidate old undo/operation handles.
                incoming.revision = max(incoming.revision, next.items[i].revision) + 1
                next.items[i] = incoming
                next.notices.removeAll { $0.itemID == incoming.id }; next.operations.removeAll { $0.itemID == incoming.id }
            } else { next.items.append(incoming) }
        }
        guard next.items.count <= KnowledgeRules.maxItems else { throw KnowledgeError.invalid("合并后超过 1,000 条，请分批整理。") }
        return next
    }
}
