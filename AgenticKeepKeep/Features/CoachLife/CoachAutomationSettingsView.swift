import SwiftData
import SwiftUI

@MainActor
struct CoachAutomationSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [Plan]
    @State private var rules = CoachAutomationRules()
    @State private var token: String?
    @State private var loaded = false
    @State private var message: String?
    @State private var editing: Editor?
    @State private var editorBaseline = CoachAutomationRules()
    @State private var keepEditorChanges = false
    private enum Editor: String, Identifiable {
        case plan, move, shorten, other, limits
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plan: return "适用课程表"
            case .move: return "调整时间"
            case .shorten: return "缩短训练"
            case .other: return "其他调整"
            case .limits: return "更多边界"
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("留一点弹性，\n训练跟上生活。").font(.title2.weight(.semibold))
                        Text("小变化交给 Milo。你的边界，始终有效。")
                            .font(.subheadline).foregroundStyle(Theme.Journal.secondary)
                    }
                    Spacer(minLength: 0); MiloAvatar(size: 64)
                }.padding(.bottom, 24)
                Toggle(isOn: $rules.enabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("范围内自动调整").font(.headline)
                        Text(rules.enabled ? "超出范围时，先问我" : "每次调整都先问我").font(.footnote).foregroundStyle(Theme.Journal.secondary)
                    }
                }.tint(Theme.accent).padding(16).background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: 16))
                row(.plan, symbol: "calendar", title: plans.first(where: { rules.planIDs.contains($0.uuid) })?.title ?? "选择适用课程表", subtitle: "只调整你选择的进行中课程表")
                heading("Milo 可以自己处理")
                row(.move, symbol: "clock", title: "调整时间", subtitle: moveSummary)
                row(.shorten, symbol: "line.3.horizontal.decrease", title: "缩短训练", subtitle: rules.actions.contains(.shorten) ? "至少\(number(rules.minimumSessionMinutes))分钟 · 最多缩短\(number(rules.maximumShorteningPercent))%" : "需要先询问")
                row(.other, symbol: "slider.horizontal.3", title: "其他调整", subtitle: otherSummary)
                heading("同时同步关联安排")
                HStack(spacing: 10) {
                    syncOption("日历", symbol: "calendar", selected: $rules.syncCalendar)
                    syncOption("训练闹钟", symbol: "alarm", selected: $rules.syncAlarms)
                }.padding(.vertical, 12)
                Text("仅限 Moveliq 关联的训练日程与闹钟；还需启用对应插件和训练同步。")
                    .font(.footnote).foregroundStyle(Theme.Journal.secondary)
                row(.limits, symbol: nil, title: "更多边界", subtitle: "未来\(number(rules.horizonDays))天 · 每天最多\(number(rules.dailyChangeLimit))项")
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.Journal.secondary).padding(.top, 16) }
            }.padding(24)
        }
        .background(Theme.Journal.canvas)
        .navigationTitle("自动调整").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button("保存我的范围") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(!loaded)
                Text("保护时段与准备缓冲始终有效").font(.caption).foregroundStyle(Theme.Journal.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 12).background(Theme.Journal.canvas)
        }
        .sheet(item: $editing, onDismiss: {
            if !keepEditorChanges { rules = editorBaseline }
        }) { editor in
            NavigationStack {
                Form {
            Group { editorContents(editor)
            }.listRowBackground(Theme.card)
        }.themedListSurface()
                    .navigationTitle(editor.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { keepEditorChanges = true; editing = nil } }
                    }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .task {
            do { token = ServiceCredentials.session?.token; rules = try CoachLifeStore.automationRules(context); loaded = true }
            catch { message = error.localizedDescription }
        }
    }
    private func number(_ value: Int?) -> String { value.map(String.init) ?? "未设定" }
    private var moveSummary: String {
        guard rules.actions.contains(.move) else { return "需要先询问" }
        return "\(rules.maximumDateShiftDays == 0 ? "同一天" : "最多跨\(number(rules.maximumDateShiftDays))天") · 前后最多\(number(rules.maximumStartShiftMinutes))分钟"
    }
    private var otherSummary: String {
        var values: [String] = []
        if rules.actions.contains(.reduceWeight) { values.append("减重最多\(number(rules.maximumWeightReductionPercent))%") }
        if rules.actions.contains(.skip) { values.append("允许跳过本次") }
        return values.isEmpty ? "减重、跳过训练都先询问" : values.joined(separator: " · ")
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Theme.Journal.metadata).padding(.top, 22)
    }
    private func row(_ editor: Editor, symbol: String?, title: String, subtitle: String) -> some View {
        Button { editorBaseline = rules; keepEditorChanges = false; editing = editor } label: {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol).frame(width: 22) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.Journal.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.Journal.metadata)
            }.frame(minHeight: 64).contentShape(Rectangle())
        }.buttonStyle(.plain).overlay(alignment: .bottom) { Divider() }
    }
    private func syncOption(_ title: String, symbol: String, selected: Binding<Bool>) -> some View {
        Button { selected.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol); Text(title)
                if selected.wrappedValue { Image(systemName: "checkmark").font(.caption) }
            }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected.wrappedValue ? Theme.Journal.panel : Theme.Journal.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.Journal.metadata, lineWidth: 0.5) }
        }.buttonStyle(.plain).accessibilityValue(selected.wrappedValue ? "已选择" : "未选择")
    }
    private func action(_ value: CoachAutomationRules.Action) -> Binding<Bool> {
        Binding(get: { rules.actions.contains(value) }, set: { if $0 { rules.actions.insert(value) } else { rules.actions.remove(value) } })
    }
    private func numeric(_ title: String, _ path: WritableKeyPath<CoachAutomationRules, Int?>) -> some View {
        HStack {
            Text(title); Spacer()
            TextField("未设定", text: Binding(get: { rules[keyPath: path].map(String.init) ?? "" }, set: { rules[keyPath: path] = Int($0) }))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
    @ViewBuilder private func editorContents(_ editor: Editor) -> some View {
        switch editor {
        case .plan:
            Section {
                Picker("适用课程表", selection: Binding<UUID?>(get: { rules.planIDs.first }, set: { rules.planIDs = $0.map { Set([$0]) } ?? [] })) {
                    Text("请选择").tag(Optional<UUID>.none)
                    ForEach(plans.filter(\.isActive), id: \.uuid) { Text($0.title).tag(Optional($0.uuid)) }
                }
            } footer: { Text("新课程表需要重新选择授权。没有进行中的课程表时，请先和 Milo 创建并确认计划。") }
        case .move:
            Section {
                Toggle("允许自动调整时间", isOn: action(.move))
                numeric("前后最多移动 · 分钟（1–10080）", \.maximumStartShiftMinutes)
                numeric("最多跨几天（0–7，0为当天）", \.maximumDateShiftDays)
            } footer: { Text("多次调整按最初的时间累计；保护时段和准备缓冲始终保留。") }
        case .shorten:
            Section {
                Toggle("允许自动缩短训练", isOn: action(.shorten))
                numeric("至少保留 · 分钟（10–180）", \.minimumSessionMinutes)
                numeric("最多缩短 · %（1–90）", \.maximumShorteningPercent)
            } footer: { Text("时长底线与最大缩短比例同时生效，不会通过反复缩短绕过你的限制。") }
        case .other:
            Section {
                Toggle("降低已有动作的重量", isOn: action(.reduceWeight))
                numeric("最多降低 · %（1–50）", \.maximumWeightReductionPercent)
                Toggle("允许跳过本次训练", isOn: action(.skip))
            } footer: { Text("换动作、加重量、增加次数仍先询问。身体不适或信息不清楚时不会直接调整。") }
        case .limits:
            Section {
                numeric("只调整未来 · 天（1–14）", \.horizonDays)
                numeric("每天最多 · 项训练（1–20）", \.dailyChangeLimit)
                numeric("开练前停止调整 · 分钟（0–1440）", \.minimumLeadMinutes)
                Toggle("设置授权有效期", isOn: Binding(get: { rules.validUntil != nil }, set: { rules.validUntil = $0 ? Date().addingTimeInterval(30 * 86400) : nil }))
                if rules.validUntil != nil {
                    DatePicker("有效至", selection: Binding(get: { rules.validUntil ?? .now }, set: { rules.validUntil = $0 }), in: Date()...)
                }
                Button("停用并清除授权", role: .destructive) { rules = CoachAutomationRules(); keepEditorChanges = true; save(); editing = nil }
            } footer: { Text("停用或修改授权后，尚未执行的自动同步会停止。已完成的记录保留。") }
        }
    }
    private func save() {
        do {
            try CoachLifeStore.checkAccount(context: context, token: token)
            if rules.enabled {
                guard rules.isValid, try CoachLifeStore.profile(context).confirmed,
                      rules.planIDs.allSatisfy({ id in plans.contains { $0.uuid == id && $0.isActive } }),
                      rules.validUntil == nil || rules.validUntil! > .now else {
                    throw CoachPluginError.unavailable("请先确认生活时段，选择进行中的课程表，并填完整允许操作与更多边界中的额度。")
                }
            }
            try CoachLifeStore.save(automationRules: rules, in: context)
            rules = try CoachLifeStore.automationRules(context)
            CoachAutomationCoordinator.shared.invalidate()
            CoachAutomationCoordinator.shared.schedule(context: context)
            message = rules.enabled ? "范围已保存。Milo 会按这些边界检查并调整。" : "已停用，每次调整都会先询问。"
        } catch { message = "范围尚未保存：\(error.localizedDescription)" }
    }
}
