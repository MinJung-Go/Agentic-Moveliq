import SwiftData
import SwiftUI

@MainActor
struct CoachAutomationResultCard: View {
    let record: CoachAutomationRecord
    @Environment(\.modelContext) private var context
    @Query private var links: [CoachTrainingLink]
    @State private var busy = false
    @State private var result: String?
    @State private var restoring = false
    private var before: [CoachAutomationDay] { CoachLifeStore.decode([CoachAutomationDay].self, record.beforeJSON) ?? [] }
    private var after: [CoachAutomationDay] { CoachLifeStore.decode([CoachAutomationDay].self, record.afterJSON) ?? [] }
    private var relevant: [CoachTrainingLink] { links.filter { link in after.contains { $0.id == link.dayID } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.restoredAt == nil ? "Milo 已按你的范围调整" : "原课程安排已恢复").font(.headline)
                    Text(CoachLifeTime.display(record.date)).font(.caption).foregroundStyle(Theme.Journal.metadata)
                }
                Spacer(); Image(systemName: record.state == "partial" ? "exclamationmark.circle" : "checkmark.circle")
            }
            if !record.reason.isEmpty { Text(record.reason).font(.subheadline).foregroundStyle(Theme.Journal.secondary) }
            ForEach(after, id: \.id) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.title).font(.subheadline.weight(.semibold))
                    if let old = before.first(where: { $0.id == day.id }) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { arrangement(old); Image(systemName: "arrow.right"); arrangement(day) }
                            VStack(alignment: .leading, spacing: 8) { arrangement(old); Image(systemName: "arrow.down"); arrangement(day) }
                        }
                    }
                }
            }
            Divider()
            Label(record.restoredAt == nil ? "课程表已保存" : "原课程已恢复", systemImage: "checkmark.circle.fill").font(.footnote)
            ForEach(relevant, id: \.uuid) { link in
                VStack(alignment: .leading, spacing: 6) {
                    if !link.calendarReceipt.isEmpty { Label(link.calendarReceipt, systemImage: "calendar") }
                    if !link.alarmReceipt.isEmpty { Label(link.alarmReceipt, systemImage: "alarm") }
                    if link.pending { Text(link.error.isEmpty ? "关联同步待完成" : link.error).foregroundStyle(Theme.Journal.secondary) }
                }.font(.footnote)
            }
            DisclosureGroup("执行记录") { Text(record.receipt).font(.footnote).frame(maxWidth: .infinity, alignment: .leading) }
            if let result { Text(result).font(.footnote).foregroundStyle(Theme.Journal.secondary) }
            if record.restoredAt == nil {
                if record.state == "partial" || record.state == "syncQueued" || relevant.contains(where: \.pending) {
                    Button(busy ? "正在补齐…" : "单次确认并重试剩余同步") { retry() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    Text("仅补齐上方安排的日历／闹钟操作，不扩大自动授权。")
                        .font(.caption).foregroundStyle(Theme.Journal.secondary)
                }
                Button("恢复原安排") { restoring = true }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
            }
            NavigationLink("修改自动调整范围") { CoachAutomationSettingsView() }.font(.footnote)
        }.padding(20).background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: 20))
            .confirmationDialog("重新检查冲突后恢复上方原安排？", isPresented: $restoring, titleVisibility: .visible) {
                Button("确认恢复原安排") {
                    do {
                        result = try CoachAutomationCoordinator.restore(record, context: context)
                        busy = true
                        Task { result = (result ?? "") + "\n" + (await TrainingScheduleSync.retry(context: context)); busy = false }
                    } catch { result = "尚未恢复：\(error.localizedDescription)" }
                }
            } message: { Text("若课程表已再次修改或原时段有冲突，会保留当前安排。") }
    }
    private func arrangement(_ day: CoachAutomationDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.start.map(CoachLifeTime.display) ?? "时间未提供").font(.subheadline.weight(.medium))
            Text(day.status == "skipped" ? "本次休息" : "\(day.minutes.map(String.init) ?? "未提供")分钟")
                .font(.caption).foregroundStyle(Theme.Journal.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func retry() {
        do {
            let token = ServiceCredentials.session?.token
            try TrainingScheduleSync.confirmRemaining(record, context: context)
            busy = true
            Task {
                let receipt = await TrainingScheduleSync.retry(context: context)
                do { try CoachLifeStore.checkAccount(context: context, token: token) }
                catch { busy = false; return }
                result = receipt; record.receipt += "\n单次确认剩余同步：" + receipt
                record.state = relevant.contains(where: \.pending) ? "partial" : "complete"
                do { try context.save() } catch { result = "系统结果请核对；回执未保存：\(error.localizedDescription)" }
                busy = false
            }
        } catch { result = "尚未重试：\(error.localizedDescription)" }
    }
}
