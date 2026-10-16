import SwiftUI
import SwiftData
import UIKit

/// 记录详情：可编辑的记录在此修改，HealthKit 同步的数据只读
struct RecordDetailView: View {

    let item: RecordItem

    var body: some View {
        Group {
            switch item.payload {
            case .workout(let session):
                WorkoutDetailView(session: session)
            case .meal(let meal):
                MealDetailView(meal: meal)
            case .metric(let metric):
                MetricDetailView(metric: metric)
            case .rawNote(let note):
                RawNoteDetailView(note: note)
            case .healthWorkout(let workout):
                HealthWorkoutDetailView(workout: workout)
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 训练

struct WorkoutDetailView: View {

    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var sortedSets: [ExerciseSet] {
        session.sets.sorted { $0.order < $1.order }
    }

    var body: some View {
        Form {
            Section("训练") {
                TextField("标题", text: $session.title)
                DatePicker("时间", selection: $session.date)
                TextField("备注", text: $session.note, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("动作") {
                ForEach(sortedSets) { set in
                    ExerciseSetEditorRow(set: set) {
                        context.delete(set)
                        try? context.save()
                    }
                }
            }

            Section {
                LabeledContent("总容量", value: "\(Format.number(session.totalVolumeKg)) kg")
            }

            Section {
                Button("删除这条记录", role: .destructive) {
                    context.delete(session)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

struct ExerciseSetEditorRow: View {

    @Bindable var set: ExerciseSet
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("动作名", text: $set.exerciseName)
                .font(Theme.Font.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                LabeledContent("重量") {
                    TextField("kg", value: $set.weightKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
                LabeledContent("次数") {
                    TextField("次", value: $set.reps, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                }
                LabeledContent("组数") {
                    TextField("组", value: $set.setCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                }
            }
            .font(Theme.Font.footnote)

            HStack(spacing: Theme.Spacing.m) {
                LabeledContent("RPE") {
                    TextField("1-10", value: $set.rpe, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                }
            }
            .font(Theme.Font.footnote)

            HStack(spacing: Theme.Spacing.m) {
                Text("估算 1RM \(Format.number(set.estimatedOneRepMax)) kg")
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()

                Spacer(minLength: 0)

                NavigationLink {
                    ExerciseDetailView(
                        name: set.exerciseName,
                        setsText: "\(set.setCount)×\(set.reps)",
                        weightKg: set.weightKg,
                        rpe: set.rpe
                    )
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(set.exerciseName)的训练参数")

                Button("删除", role: .destructive, action: onDelete)
                    .font(Theme.Font.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 饮食

struct MealDetailView: View {

    @Bindable var meal: MealEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isPhotoPresented = false

    var body: some View {
        Form {
            if let data = meal.photoData, let image = UIImage(data: data) {
                Section("照片") {
                    Button {
                        isPhotoPresented = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $isPhotoPresented) {
                    PhotoViewer(image: image)
                }
            }

            Section("这一餐") {
                Picker("餐次", selection: $meal.mealType) {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                DatePicker("时间", selection: $meal.date)
            }

            Section("食物") {
                ForEach(meal.items) { item in
                    FoodItemEditorRow(item: item) {
                        context.delete(item)
                        try? context.save()
                    }
                }
            }

            Section("合计") {
                LabeledContent("热量", value: "\(Format.number(meal.totalCalories)) kcal")
                LabeledContent("蛋白质", value: "\(Format.number(meal.totalProteinG)) g")
                LabeledContent("碳水", value: "\(Format.number(meal.totalCarbsG)) g")
                LabeledContent("脂肪", value: "\(Format.number(meal.totalFatG)) g")
            }

            Section {
                Text("热量与营养素为 AI 估算值，可逐项修正")
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.tertiaryLabel)
            }

            Section {
                Button("删除这条记录", role: .destructive) {
                    context.delete(meal)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

/// 全屏查看照片
struct PhotoViewer: View {

    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Font.title)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct FoodItemEditorRow: View {

    @Bindable var item: FoodItem
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("食物名", text: $item.name)
                .font(Theme.Font.subheadline.weight(.semibold))

            LabeledContent("分量") {
                TextField("如 1 碗", text: $item.amountText)
                    .multilineTextAlignment(.trailing)
            }
            .font(Theme.Font.footnote)

            HStack(spacing: 12) {
                LabeledContent("热量") {
                    TextField("kcal", value: $item.calories, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                LabeledContent("蛋白") {
                    TextField("g", value: $item.proteinG, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                }
            }
            .font(Theme.Font.footnote)

            HStack {
                if item.isEstimated {
                    RecordSourceLabel(text: "AI 估算")
                }
                Spacer()
                Button("删除", role: .destructive, action: onDelete)
                    .font(Theme.Font.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 指标

struct MetricDetailView: View {

    @Bindable var metric: BodyMetric
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("指标") {
                Picker("类型", selection: $metric.kind) {
                    ForEach(MetricKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                LabeledContent("数值") {
                    TextField(metric.kind.unit, value: $metric.value, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("时间", selection: $metric.date)
                TextField("备注", text: $metric.note)
            }

            Section {
                Button("删除这条记录", role: .destructive) {
                    context.delete(metric)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 待归类笔记

struct RawNoteDetailView: View {

    @Bindable var note: RawNote
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var message: String?

    private let settings = LLMSettings.shared

    var body: some View {
        Form {
            Section("原文") {
                if let data = note.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                }
                TextField("内容", text: $note.text, axis: .vertical)
                    .lineLimit(3...8)
                DatePicker("时间", selection: $note.date)
                if !note.failureReason.isEmpty {
                    LabeledContent("上次失败原因", value: note.failureReason)
                        .font(Theme.Font.footnote)
                }
            }

            Section {
                Button {
                    if let photo = note.photoData {
                        appState.pendingLogText = note.text
                        appState.pendingLogPhoto = photo
                        appState.isQuickLogPresented = true
                    } else {
                        Task { await reparse() }
                    }
                } label: {
                    HStack {
                        Label("用 AI 重新解析", systemImage: "wand.and.stars")
                        if isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(isWorking || !settings.isConfigured)

                Button("标记为已处理") {
                    note.status = .categorized
                    try? context.save()
                    dismiss()
                }
            } footer: {
                if !settings.isConfigured {
                    Text("请先在设置中准备好离线模型或云端 AI")
                } else if let message {
                    Text(message)
                } else {
                    Text("解析成功后会生成训练/饮食等记录，并把这则笔记标记为已归类")
                }
            }

            Section {
                Button("删除", role: .destructive) {
                    context.delete(note)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func reparse() async {
        isWorking = true
        message = nil
        defer { isWorking = false }

        do {
            let client = try settings.makeRecordingClient()
            let records = try await ParserAgent(client: client).parse(note.text, now: note.date)
            let summary = try RecordImporter.apply(records, to: context, date: note.date)
            guard summary.total > 0 else {
                message = "这次没有解析出可归档的内容，原文已保留"
                return
            }
            note.status = .categorized
            try context.save()
            message = "已归类为 \(summary.total) 条记录"
        } catch {
            note.failureReason = error.localizedDescription
            try? context.save()
            message = "解析失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - HealthKit 运动（只读）

struct HealthWorkoutDetailView: View {

    let workout: HealthWorkout

    var body: some View {
        Form {
            Section("运动") {
                LabeledContent("类型", value: workout.activityName)
                LabeledContent("开始时间", value: Format.shortDay(workout.date) + " " + Format.time(workout.date))
                LabeledContent("时长", value: workout.durationText)
                if let km = workout.distanceKm {
                    LabeledContent("距离", value: "\(Format.number(km, decimals: 2)) km")
                }
                if let pace = workout.paceText {
                    LabeledContent("配速", value: pace)
                }
                if let heartRate = workout.averageHeartRate {
                    LabeledContent("平均心率", value: "\(Format.number(heartRate)) bpm")
                }
                LabeledContent("来源", value: workout.sourceName)
            }

            Section {
                Text("来自 HealthKit 的运动记录，此处只读。要修改请到「健康」App。")
                    .font(Theme.Font.badge)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
    }
}
