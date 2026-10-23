import Foundation
import SwiftData

@MainActor
enum CoachPluginExecutor {
    private static var performing = Set<UUID>()
    static func execute(_ call: LLMToolCall, context: ModelContext, token: String?, allowsNearby: Bool = false, conversationID: UUID? = nil) async throws -> CoachToolResult {
        try CoachLifeStore.checkAccount(context: context, token: token)
        guard call.argumentsJSON.utf8.count <= 4096 else { throw CoachPluginError.invalid }
        let object = try JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any] ?? [:]
        let config = try CoachLifeStore.plugins(context)
        func require(_ plugin: CoachPlugin) throws { try CoachLifeStore.require(plugin, context: context, token: token) }
        func proposed(_ kind: String, _ payload: CoachActionPayload) throws -> CoachToolResult {
            let record = try CoachLifeStore.action(kind: kind, payload: payload, in: context, conversationID: conversationID)
            return CoachToolResult(content: "操作卡\(record.uuid)已准备：\(payload.title)。尚未执行，用户确认后才生效。请简要说明，不声称已完成。")
        }
        switch call.name {
        case CoachPluginTools.life.name:
            return CoachToolResult(content: try CoachLifeContextBuilder.summary(context: context, days: object["days"] as? Int ?? 7))
        case CoachPluginTools.calendar.name:
            try require(.calendar)
            guard let start = (object["start"] as? String).flatMap(CoachLifeTime.date), let end = (object["end"] as? String).flatMap(CoachLifeTime.date) else { throw CoachPluginError.invalid }
            return CoachToolResult(content: try CalendarPluginService.shared.query(start: start, end: end, config: config, profile: CoachLifeStore.profile(context)))
        case CoachPluginTools.calendarChange.name:
            try require(.calendar)
            guard let request = CoachAgent.decodeArguments(CalendarChangeRequest.self, from: call) else { throw CoachPluginError.invalid }
            let target = try request.eventToken.map { try CalendarPluginService.shared.resolve(token: $0, config: config) }
            try CalendarPluginService.shared.validate(request, target: target)
            return try proposed("calendar", CoachActionPayload(calendar: request, event: target, title: request.title ?? target?.title ?? "日程", reason: String((object["reason"] as? String ?? "").prefix(500))))
        case CoachPluginTools.alarms.name:
            try require(.alarms)
            let ids = try AlarmPluginService.scheduledIDs(), owned = try ownedAlarmIDs(context)
            return CoachToolResult(content: ids.intersection(owned).isEmpty ? "当前账号没有仍由系统安排的Moveliq闹钟；不代表系统时钟App没有闹钟。" : ids.intersection(owned).map { "alarmID=\($0.uuidString)" }.joined(separator: "\n"))
        case CoachPluginTools.alarmChange.name:
            try require(.alarms)
            guard let request = CoachAgent.decodeArguments(AlarmChangeRequest.self, from: call) else { throw CoachPluginError.invalid }
            try AlarmPluginService.validate(request)
            if request.action != "create" {
                guard let id = request.alarmID.flatMap(UUID.init(uuidString:)), try ownedAlarmIDs(context).contains(id), try AlarmPluginService.scheduledIDs().contains(id) else { throw CoachPluginError.stale }
            }
            return try proposed("alarms", CoachActionPayload(alarm: request, title: request.title ?? "取消已选闹钟", reason: String((object["reason"] as? String ?? "").prefix(500))))
        case CoachPluginTools.places.name:
            try require(.maps)
            guard let query = object["query"] as? String, let nearby = object["nearby"] as? Bool else { throw CoachPluginError.invalid }
            guard !nearby || allowsNearby else { throw CoachPluginError.unavailable("用户尚未要求使用当前位置。请先询问，或使用明确地点名称。") }
            let found = try await MapsPluginService.shared.search(query, nearby: nearby, revalidate: { try require(.maps) })
            return CoachToolResult(content: found.isEmpty ? "未找到地点，不能编造来源。" : found.map { "placeToken=\($0.id)；\($0.name)；\($0.address)" }.joined(separator: "\n"), failed: found.isEmpty)
        case CoachPluginTools.mapOpen.name:
            try require(.maps)
            guard let key = object["placeToken"] as? String, let transport = object["transport"] as? String, ["walking", "driving", "transit", "cycling"].contains(transport) else { throw CoachPluginError.invalid }
            let place = try MapsPluginService.shared.place(key)
            let origin = try (object["startPlaceToken"] as? String).map { try MapsPluginService.shared.place($0) }
            return try proposed("maps", CoachActionPayload(placeLatitude: place.coordinate.latitude, placeLongitude: place.coordinate.longitude,
                originLatitude: origin?.coordinate.latitude, originLongitude: origin?.coordinate.longitude, originTitle: origin?.name,
                transport: transport, title: place.name))
        case CoachPluginTools.music.name:
            try require(.music)
            guard let query = object["query"] as? String else { throw CoachPluginError.invalid }
            let found = try await MusicPluginService.shared.search(query, revalidate: { try require(.music) })
            return CoachToolResult(content: MusicPluginService.shared.notice + "\n" + (found.isEmpty ? "没有可用结果。" : found.map { "musicToken=\($0.id)；\($0.kind)：\($0.title)；\($0.subtitle)" }.joined(separator: "\n")), failed: found.isEmpty)
        case CoachPluginTools.musicPlay.name:
            try require(.music)
            guard let key = object["musicToken"] as? String else { throw CoachPluginError.invalid }
            let choice = try MusicPluginService.shared.choice(key)
            return try proposed("music", CoachActionPayload(musicID: key, musicKind: choice.kind, title: choice.title, reason: "将替换 Apple 音乐当前播放队列。"))
        case CoachPluginTools.musicControl.name:
            try require(.music)
            guard let action = object["action"] as? String else { throw CoachPluginError.invalid }
            if action == "status" { return CoachToolResult(content: try await MusicPluginService.shared.control(action, revalidate: { try require(.music) })) }
            let titles = ["pause": "暂停音乐", "resume": "继续播放", "next": "下一首", "previous": "上一首"]
            guard let title = titles[action] else { throw CoachPluginError.invalid }
            return try proposed("music", CoachActionPayload(musicControl: action, title: title))
        default: throw CoachPluginError.invalid
        }
    }
    static func ownedAlarmIDs(_ context: ModelContext) throws -> Set<UUID> {
        let actions = try context.fetch(FetchDescriptor<CoachActionRecord>()).filter { $0.kind == "alarms" && ["succeeded", "partial", "executing"].contains($0.state) }
        let links = try context.fetch(FetchDescriptor<CoachTrainingLink>())
        return Set(actions.map(\.operationID) + links.compactMap(\.alarmID) + links.flatMap(\.retiredAlarmIDs))
    }
    static func perform(_ record: CoachActionRecord, scope: String, transport: String? = nil, context: ModelContext) async throws {
        let token = ServiceCredentials.session?.token
        guard !performing.contains(record.uuid), ["pending", "partial", "executing"].contains(record.state),
              let plugin = CoachPlugin(rawValue: record.kind), let payload = CoachLifeStore.decode(CoachActionPayload.self, record.payloadJSON) else { throw CoachPluginError.invalid }
        try CoachLifeStore.require(plugin, context: context, token: token)
        if record.expiresAt < .now { throw CoachPluginError.stale }
        if ["partial", "executing"].contains(record.state), ["next", "previous"].contains(payload.musicControl ?? "") {
            throw CoachPluginError.unavailable("上次切歌的结果尚未确认。请查看当前播放状态后重新选择，避免重复切歌。")
        }
        performing.insert(record.uuid); defer { performing.remove(record.uuid) }
        record.state = "executing"; try context.save()
        do {
            func revalidate() throws { try CoachLifeStore.require(plugin, context: context, token: token); try Task.checkCancellation() }
            try revalidate()
            let receipt: String
            switch plugin {
            case .calendar:
                guard let request = payload.calendar else { throw CoachPluginError.invalid }
                receipt = try CalendarPluginService.shared.apply(request, target: payload.event, config: CoachLifeStore.plugins(context), scope: scope, operationID: record.operationID)
            case .alarms:
                guard let request = payload.alarm else { throw CoachPluginError.invalid }
                if request.action == "cancel" {
                    guard let id = request.alarmID.flatMap(UUID.init(uuidString:)), try ownedAlarmIDs(context).contains(id) else { throw CoachPluginError.stale }
                    try AlarmPluginService.cancel(id); receipt = "已取消所选 Moveliq 闹钟。"
                } else {
                    if request.action == "update" {
                        guard let id = request.alarmID.flatMap(UUID.init(uuidString:)), try ownedAlarmIDs(context).contains(id) else { throw CoachPluginError.stale }
                    }
                    try await AlarmPluginService.schedule(request, id: record.operationID)
                    try revalidate()
                    if request.action == "update", let old = request.alarmID.flatMap(UUID.init(uuidString:)) { try AlarmPluginService.cancel(old) }
                    receipt = "系统已安排：\(payload.title)。"
                }
            case .maps:
                guard let a = payload.placeLatitude, let b = payload.placeLongitude else { throw CoachPluginError.invalid }
                try await MapsPluginService.shared.open(latitude: a, longitude: b, title: payload.title, transport: transport ?? payload.transport ?? "walking",
                    originLatitude: payload.originLatitude, originLongitude: payload.originLongitude, originTitle: payload.originTitle)
                receipt = "已打开 Apple 地图路线，尚不代表开始导航。"
            case .music:
                if let control = payload.musicControl { receipt = try await MusicPluginService.shared.control(control, revalidate: revalidate) }
                else {
                    guard let key = payload.musicID else { throw CoachPluginError.invalid }
                    try await MusicPluginService.shared.play(key, revalidate: revalidate)
                    receipt = "已交给 Apple 音乐播放：\(payload.title)。"
                }
            case .browser: throw CoachPluginError.invalid
            }
            try revalidate()
            record.state = "succeeded"; record.receipt = receipt; record.completedAt = Date()
            do { try context.save() }
            catch { record.receipt += " 回执未能保存，重新打开后请先核对系统状态。"; throw error }
            if let conversation = record.conversationID {
                // A learning failure must not turn a completed system operation into a failed one.
                do { try PersonalLearningCoordinator.shared.enqueue(conversation: conversation, context: context) }
                catch { record.receipt += " 记忆整理未能排队，可在记忆页面手动整理此对话。"; try? context.save() }
            }
        } catch {
            if record.state != "succeeded" {
                record.state = "partial"
                record.receipt = "尚未全部完成：\(error.localizedDescription)"
                try? context.save()
            }
            throw error
        }
    }
}
