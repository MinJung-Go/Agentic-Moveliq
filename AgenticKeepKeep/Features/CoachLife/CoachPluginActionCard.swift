import MapKit
import SwiftData
import SwiftUI

@MainActor
struct CoachPluginActionCard: View {
    let action: CoachActionRecord
    @Environment(\.modelContext) private var context
    @State private var scope = ""
    @State private var transport = ""
    @State private var busy = false
    @State private var error: String?
    private var payload: CoachActionPayload? { CoachLifeStore.decode(CoachActionPayload.self, action.payloadJSON) }
    private var pending: Bool { ["pending", "partial", "executing"].contains(action.state) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(pending ? "待确认 · \(CoachPlugin(rawValue: action.kind)?.title ?? "操作")" : (action.state == "rejected" ? "未采用" : "操作结果"), systemImage: CoachPlugin(rawValue: action.kind)?.symbol ?? "checkmark.circle")
                .font(.caption).foregroundStyle(Theme.secondaryLabel)
            if let payload {
                Text(payload.title).font(.headline)
                if !payload.reason.isEmpty { Text(payload.reason).font(.subheadline) }
                details(payload)
                if !action.receipt.isEmpty { Text(action.receipt).font(.footnote).foregroundStyle(Theme.secondaryLabel) }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                if pending {
                    if payload.event?.recurring == true {
                        Picker("重复范围", selection: $scope) {
                            Text("请选择范围").tag(""); Text("仅此次").tag("this"); Text("此次及以后").tag("future")
                        }.pickerStyle(.menu)
                    }
                    Button(busy ? "正在处理…" : confirmTitle(payload)) { Task { await perform() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || (payload.event?.recurring == true && scope.isEmpty))
                    Button("不采用") {
                        action.state = "rejected"
                        do { try context.save() } catch { self.error = error.localizedDescription; action.state = "pending" }
                    }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                }
            } else { Text("提案无法读取，请重新生成。").foregroundStyle(Theme.danger) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { if transport.isEmpty { transport = payload?.transport ?? "walking" } }
    }
    @ViewBuilder private func details(_ payload: CoachActionPayload) -> some View {
        if let event = payload.event {
            Text("原日程：\(CoachLifeTime.display(event.start)) — \(CoachLifeTime.display(event.end))\n日历：\(event.calendarTitle)\(event.allDay ? " · 全天" : "")").font(.footnote)
        }
        if let calendar = payload.calendar {
            if let start = calendar.start.flatMap(CoachLifeTime.date), let end = calendar.end.flatMap(CoachLifeTime.date) {
                Text("\(calendar.action == "create" ? "新建" : "调整为")：\(CoachLifeTime.display(start)) — \(CoachLifeTime.display(end))").font(.subheadline)
            }
            if calendar.action == "delete" { Text("将删除所选日程范围。此操作会同步到该日历所属账号。").foregroundStyle(Theme.danger).font(.footnote) }
            if let minutes = calendar.reminderMinutes { Text("提前 \(minutes) 分钟提醒").font(.footnote) }
            if let recurrence = calendar.recurrence, recurrence != "none" {
                Text("\(recurrence == "daily" ? "每天" : "每周")重复，至 \(calendar.repeatUntil.flatMap(CoachLifeTime.date).map(CoachLifeTime.display) ?? "未提供")").font(.footnote)
            }
            if calendar.action == "create" {
                Text("写入日历：\((try? CoachLifeStore.plugins(context)).flatMap { CalendarPluginService.shared.store.calendar(withIdentifier: $0.writeCalendarID)?.title } ?? "尚未选择")").font(.footnote)
            }
        }
        if let alarm = payload.alarm {
            if let at = alarm.date.flatMap(CoachLifeTime.date) { Text(CoachLifeTime.display(at)) }
            if let time = alarm.time { Text("当地时间 \(time) · 星期：\((alarm.weekdays ?? []).filter { (1...7).contains($0) }.map { ["", "日", "一", "二", "三", "四", "五", "六"][$0] }.joined(separator: "、"))") }
            if let minutes = alarm.countdownMinutes { Text("确认后 \(minutes) 分钟提醒") }
            if let id = alarm.alarmID { Text("目标：\(id)").font(.caption).textSelection(.enabled) }
            Text("仅管理当前账号的 Moveliq 闹钟。").font(.caption).foregroundStyle(Theme.secondaryLabel)
        }
        if let latitude = payload.placeLatitude, let longitude = payload.placeLongitude {
            Text("起点：\(payload.originTitle ?? "在 Apple 地图选择或修改")").font(.footnote)
            Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: latitude, longitude: longitude), span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))) {
                Marker(payload.title, coordinate: .init(latitude: latitude, longitude: longitude))
            }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
            if pending {
                Picker("出行方式", selection: $transport) {
                    Text("步行").tag("walking"); Text("骑行").tag("cycling"); Text("驾车").tag("driving"); Text("公共交通").tag("transit")
                }
            }
            Text("在 Apple 地图查看路线详情，并可修改起点。").font(.footnote)
        }
        if payload.musicID != nil { Text("\(payload.musicKind ?? "音乐") · 确认后替换 Apple 音乐的当前播放队列。").font(.footnote) }
    }
    private func confirmTitle(_ payload: CoachActionPayload) -> String {
        if payload.calendar?.action == "delete" { return "确认删除日程" }
        if payload.alarm?.action == "cancel" { return "确认取消闹钟" }
        if action.kind == "maps" { return "在 Apple 地图查看路线" }
        if payload.musicControl != nil { return "确认\(payload.title)" }
        if action.kind == "music" { return "确认播放" }
        return action.state == "partial" || action.state == "executing" ? "核对并重试未完成项" : "确认操作"
    }
    private func perform() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { try await CoachPluginExecutor.perform(action, scope: scope, transport: transport.isEmpty ? nil : transport, context: context) }
        catch { self.error = error.localizedDescription }
    }
}
