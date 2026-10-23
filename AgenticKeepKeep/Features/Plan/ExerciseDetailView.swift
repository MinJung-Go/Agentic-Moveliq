import SwiftUI
import SwiftData

/// 通用详情只读取传入的训练参数，不依赖第三方图库。
struct ExerciseDetailView: View {
    let name: String
    var setsText: String?
    var weightKg: Double?
    var rpe: Double?

    var body: some View {
        List {
            Group {
            Section {
                Text(name.isEmpty ? "未命名动作" : name)
                    .font(Theme.Font.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("训练安排") {
                LabeledContent("组次", value: setsText.flatMap { $0.isEmpty ? nil : $0 } ?? "未设置")
                LabeledContent("重量", value: weightKg.map { "\(Format.number($0)) kg" } ?? "未设置")
                if let rpe {
                    LabeledContent("主观强度 RPE", value: Format.number(rpe))
                }
            }
            ExerciseTutorialSection(name: name)

            }.listRowBackground(Theme.card)
        }.themedListSurface()
        .navigationTitle("动作详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlanExerciseDetailView: View {
    let exercise: PlanExercise
    @State private var isEditing = false

    var body: some View {
        ExerciseDetailView(name: exercise.name, setsText: exercise.setsText, weightKg: exercise.targetWeightKg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                PlanExerciseEditor(exercise: exercise)
            }
    }
}

private struct PlanExerciseEditor: View {
    let exerciseID: UUID
    @State private var draft: PlanExerciseEditDraft
    @State private var errorMessage: String?
    private enum Field: Hashable { case name, sets, weight }
    @FocusState private var focusedField: Field?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(exercise: PlanExercise) {
        exerciseID = exercise.uuid
        _draft = State(initialValue: PlanExerciseEditDraft(exercise))
    }

    var body: some View {
        NavigationStack {
            Form {
            Group {
                Section("动作") {
                    TextField("动作名称", text: $draft.name)
                        .focused($focusedField, equals: .name)
                    TextField("组次，如 4×10 或 3×30秒", text: $draft.setsText)
                        .focused($focusedField, equals: .sets)
                }
                Section {
                    TextField("重量（kg），可留空", text: $draft.weightText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                } header: { Text("目标重量") } footer: {
                    Text("留空表示未设置，0 表示不使用额外负重。")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                    }
                }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try PlanExerciseStore.save(draft, id: exerciseID, context: context)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(name: "杠铃卧推", setsText: "4×8", weightKg: 60)
    }
}
