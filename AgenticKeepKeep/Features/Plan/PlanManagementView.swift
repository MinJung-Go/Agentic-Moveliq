import SwiftUI
import SwiftData

struct PlanDeletionTarget: Identifiable {
    let id: UUID
    let title: String
    init(_ plan: Plan) { id = plan.uuid; title = plan.title }
}

struct PlanManagementView: View {
    @Query(sort: [SortDescriptor(\Plan.createdAt, order: .reverse)]) private var plans: [Plan]
    @State private var pendingDeletion: PlanDeletionTarget?

    var body: some View {
        List {
            Group {
            ForEach(plans) { plan in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(plan.title)
                    Text("\(plan.isActive ? "进行中" : "已归档") · \(plan.days.count) 个训练日")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.secondaryLabel)
                }
                .swipeActions {
                    Button("删除", role: .destructive) { pendingDeletion = PlanDeletionTarget(plan) }
                }
            }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
        .overlay { if plans.isEmpty { ContentUnavailableView("没有课程表", systemImage: "calendar") } }
        .navigationTitle("管理课程表")
        .navigationBarTitleDisplayMode(.inline)
        .confirmPlanDeletion($pendingDeletion)
    }
}

private struct PlanDeletionConfirmation: ViewModifier {
    @Binding var target: PlanDeletionTarget?
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("删除课程表？", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), presenting: target) { value in
                Button("删除《\(value.title)》", role: .destructive) {
                    do {
                        try PlanMutationStore.delete(id: value.id, context: context)
                        appState.showToast("课程表已删除，训练记录已保留")
                        do {
                            try TrainingScheduleSync.enqueue(planID: value.id, context: context)
                            Task { appState.showToast(await TrainingScheduleSync.retry(context: context)) }
                        } catch { appState.showToast("课程表已删除，关联日历与提醒清理待处理：\(error.localizedDescription)") }
                    } catch { self.error = error.localizedDescription }
                    target = nil
                }
                Button("取消", role: .cancel) { target = nil }
            } message: { _ in
                Text("将删除这份计划及其训练日、动作，并清理 Moveliq 关联的未来日程与闹钟。已有训练记录和 Apple 健康数据会保留；同步失败可在今日安排重试。")
            }
            .alert("删除失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) { error = nil }
            } message: { Text(error ?? "请重试") }
    }
}

extension View {
    func confirmPlanDeletion(_ target: Binding<PlanDeletionTarget?>) -> some View {
        modifier(PlanDeletionConfirmation(target: target))
    }
}
