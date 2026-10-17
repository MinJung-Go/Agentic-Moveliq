import SwiftData
import SwiftUI

/// 训练执行页：跟着计划练，逐组打勾。
///
/// 设计目标是**一屏做完一组**：示范图、组次、主按钮都在视野内，不用滚动。
/// 默认值全部来自计划，一路点「完成这组」就能走完；想改才去改输入框。
struct WorkoutSessionView: View {

    let planDay: PlanDay

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: WorkoutSessionViewModel

    @State private var isDiscardConfirmPresented = false
    @State private var showsFeedback = false

    init(planDay: PlanDay) {
        self.planDay = planDay
        _model = StateObject(wrappedValue: WorkoutSessionViewModel(
            planDay: planDay,
            context: planDay.modelContext ?? AppModelContainer.shared.mainContext
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                if let reason = model.unavailableReason {
                    unavailableCard(reason)
                } else {
                    exerciseSelector
                    currentExerciseCard
                    setListCard
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.canvas)
        .navigationTitle(model.draft.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("结束") { finishOrDiscard() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.unavailableReason == nil {
                completeButton
            }
        }
        .sheet(isPresented: $model.isSummaryPresented, onDismiss: {
            if model.completedSessionID != nil { showsFeedback = true }
        }) {
            summarySheet
        }
        .sheet(isPresented: $showsFeedback, onDismiss: { if model.completedSessionID != nil { dismiss() } }) {
            NavigationStack {
                CoachFeedbackView(sessionID: model.completedSessionID, dayID: planDay.uuid, suggestedMinutes: max(1, Int(model.summary.duration / 60)))
            }
        }
        .confirmationDialog(
            "还没有完成任何一组",
            isPresented: $isDiscardConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("放弃这次训练", role: .destructive) {
                model.discard()
                dismiss()
            }
            Button("继续练", role: .cancel) {}
        } message: {
            Text("这次训练不会留下记录。")
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(model.positionText)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
            Spacer(minLength: 0)
            // 每分钟刷一次就够，没必要每秒重排
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(model.elapsedText)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
        }
    }

    /// 动作切换：点一下就跳过去，允许跳过某个动作（FR2.6）
    private var exerciseSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Array(model.engine.exercises.enumerated()), id: \.element.id) { index, exercise in
                    let isCurrent = index == model.engine.currentIndex
                    let isDone = model.engine.isExerciseFinished(exercise)

                    Button {
                        model.moveTo(index: index)
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(exercise.name)
                                .lineLimit(1)
                        }
                        .font(Theme.Font.badge)
                        .foregroundStyle(isCurrent ? Theme.onAccent : Theme.secondaryLabel)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 6)
                        .background(
                            isCurrent ? Theme.accent : Theme.chip,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - 当前动作

    private var currentExerciseCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let exercise = model.currentExercise {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        NavigationLink {
                            ExerciseDetailView(
                                name: exercise.name,
                                setsText: exercise.setsText,
                                weightKg: exercise.plannedWeightKg
                            )
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(exercise.name)
                                    .font(Theme.Font.headline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(plannedDescription(exercise))
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .monospacedDigit()

                        HStack(spacing: Theme.Spacing.xs) {
                            if let setIndex = model.currentSetIndex(for: exercise) {
                                Badge("第 \(setIndex) 组", tone: .bright(Theme.accent))
                            } else {
                                Badge("已做完", tone: .solid(Theme.positive))
                            }
                        }

                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .card()
    }

    private func plannedDescription(_ exercise: WorkoutSessionEngine.Exercise) -> String {
        var parts: [String] = []
        if let weight = exercise.plannedWeightKg, weight > 0 {
            parts.append("\(Format.number(weight, decimals: weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) kg")
        }
        if let sets = exercise.plannedSets, let reps = exercise.plannedReps {
            parts.append("\(sets) 组 × \(reps) 次")
        } else if !exercise.setsText.isEmpty {
            // 解析不出组次就显示原文，不编造
            parts.append(exercise.setsText)
        }
        return parts.isEmpty ? "计划里没写组次" : parts.joined(separator: " · ")
    }

    // MARK: - 逐组列表

    private var setListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let exercise = model.currentExercise {
                let done = model.completedSets(for: exercise)
                let currentSet = model.currentSetIndex(for: exercise)
                let total = max(exercise.plannedSets ?? done.count, done.count)

                ForEach(1...max(total, 1), id: \.self) { index in
                    let record = done.first { $0.setIndex == index }

                    setRow(
                        index: index,
                        record: record,
                        isCurrent: index == currentSet
                    )

                    if index < max(total, 1) { RowDivider(inset: 0) }
                }
            }
        }
        .card(padding: 0)
    }

    @ViewBuilder
    private func setRow(
        index: Int,
        record: WorkoutSessionEngine.CompletedSet?,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("第 \(index) 组")
                .font(Theme.Font.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(record != nil || isCurrent ? Color.primary : Theme.tertiaryLabel)
                .frame(width: 62, alignment: .leading)

            if let record {
                Text("\(Format.number(record.weightKg, decimals: record.weightKg.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) kg × \(record.reps)")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            } else if isCurrent {
                // 当前这组可直接改 —— 默认值已经填好，不改就一路点下去（FR3.1 / FR3.2）
                HStack(spacing: Theme.Spacing.xs) {
                    TextField("kg", text: $model.draftWeightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 58)
                    Text("kg ×").foregroundStyle(Theme.secondaryLabel)
                    TextField("次", text: $model.draftRepsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                }
                .font(Theme.Font.subheadline)
                .monospacedDigit()
            } else {
                Text("—").font(Theme.Font.subheadline).foregroundStyle(Theme.tertiaryLabel)
            }

            Spacer(minLength: 0)

            if record != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.positive, in: Circle())
                    .accessibilityLabel("第 \(index) 组已完成")
            } else {
                Circle()
                    .strokeBorder(isCurrent ? Theme.accent : Theme.tertiaryLabel, lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(isCurrent ? "第 \(index) 组待做" : "第 \(index) 组未开始")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - 主按钮

    private var completeButton: some View {
        VStack(spacing: Theme.Spacing.s) {
            if model.isAllFinished {
                Button("练完了，结束") { model.isSummaryPresented = true }
                    .buttonStyle(PrimaryButtonStyle())
            } else if let exercise = model.currentExercise, model.currentSetIndex(for: exercise) == nil {
                // 这个动作按计划做完了，主按钮变成「切下一个」
                Button("下一个动作") { model.advanceToNextUnfinished() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("完成这组") { model.completeCurrentSet() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.currentExercise == nil)
            }

            if model.hasAnyProgress {
                Button("撤回上一组") { model.undoLastSet() }
                    .buttonStyle(PlainActionButtonStyle(font: Theme.Font.footnote, tint: Theme.secondaryLabel))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                Theme.canvas
            }
        }
    }

    // MARK: - 汇总

    private var summarySheet: some View {
        let summary = model.summary
        return VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.positive)
                Text("练完了")
                    .font(Theme.Font.headline)
            }

            HStack(spacing: Theme.Spacing.s) {
                summaryTile(title: "时长", value: "\(max(1, Int(summary.duration / 60)))", unit: "分钟")
                summaryTile(title: "动作", value: "\(summary.exerciseCount)", unit: "个")
                summaryTile(title: "总容量", value: Format.number(summary.totalVolumeKg), unit: "kg")
            }

            Text("完成 \(summary.setCount) 组")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.s) {
                Button("保存并结束") {
                    guard model.finish(planDay: planDay) else { return }
                    model.isSummaryPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                if let error = model.completionError { Text(error).font(.footnote).foregroundStyle(Theme.danger) }

                Button("继续练") { model.isSummaryPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.canvas)
        .presentationDetents([.medium])
    }

    private func summaryTile(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Font.badge)
                .fontWeight(.regular)
                .foregroundStyle(Theme.secondaryLabel)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Font.metric)
                Text(unit)
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 11)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }

    // MARK: - 动作

    private func finishOrDiscard() {
        if model.hasAnyProgress {
            model.isSummaryPresented = true
        } else {
            isDiscardConfirmPresented = true
        }
    }

    private func unavailableCard(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.tertiaryLabel)
            Text(reason)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
