import SwiftUI

struct CoachToolActivityView: View {
    let activities: [CoachToolActivity]
    let showThinking: Bool
    private var visible: [CoachToolActivity] { activities.filter { showThinking || $0.kind != "thinking" } }
    @State private var expanded: Bool

    init(activities: [CoachToolActivity], initiallyExpanded: Bool = false, showThinking: Bool = true) {
        self.activities = activities
        self.showThinking = showThinking
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var running: Bool { activities.contains { $0.status == .running } }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(visible) { activity in
                    if activity.kind == "thinking" {
                        CoachThinkingStep(activity: activity)
                    } else {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        if activity.status == .running {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: activity.status == .completed ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(activity.status == .completed ? Theme.secondaryLabel : Theme.warning)
                        }
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(activity.title)
                            Text(status(activity)).foregroundStyle(Theme.secondaryLabel)
                        }
                        Spacer(minLength: 0)
                        if let duration = activity.duration {
                            Text("\(Format.number(duration, decimals: 1)) 秒")
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                }
                    }
            }
            .font(Theme.Font.footnote)
            .padding(.top, Theme.Spacing.s)
        } label: {
            Label(running ? "处理中…" : "处理过程 · \(activities.filter { $0.kind != "thinking" }.count) 次工具调用", systemImage: "list.bullet.rectangle")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .tint(Theme.secondaryLabel)
    }

    private func status(_ activity: CoachToolActivity) -> String {
        switch activity.status {
        case .running: return "进行中"
        case .completed: return "执行完成"
        case .failed: return activity.failureReason.map { "查询失败：" + $0 } ?? "查询失败"
        case .cancelled: return "已取消"
        }
    }
}

private struct CoachThinkingStep: View {
    let activity: CoachToolActivity
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(activity.reasoning ?? "")
                .font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled).lineSpacing(5)
        } label: {
            HStack {
                if activity.status == .running { ProgressView().controlSize(.small) }
                Text(activity.status == .running ? "思考中" : "思考")
                Spacer()
                if let duration = activity.duration {
                    Text("\(Format.number(duration, decimals: 1)) 秒").monospacedDigit()
                }
                if activity.status == .cancelled { Text("已停止") }
                if activity.status == .failed { Text("已中断") }
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { expanded = activity.status == .running }
        .onChange(of: activity.status) { _, status in if status != .running { expanded = false } }
    }
}
