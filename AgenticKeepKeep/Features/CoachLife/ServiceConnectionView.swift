import EventKit
import SwiftData
import SwiftUI
import UIKit

struct ServiceConnectionView: View {
    var onFinish: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ServiceConnectionModel()
    @ObservedObject private var calendar = CalendarPluginService.shared
    @State private var details = false
    @State private var resultDetails = false
    @AppStorage(MiloPersona.nameKey) private var miloName = "Milo"
    private var onboarding: Bool { onFinish != nil }

    var body: some View {
        VStack(spacing: 0) {
            if onboarding {
                HStack(spacing: 7) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Text("Moveliq").font(.caption.weight(.semibold))
                    Spacer()
                    Text("你的运动伙伴").font(.caption).foregroundStyle(Theme.Journal.secondary)
                }.padding(.horizontal, 24).padding(.top, 8)
            }
            HStack(spacing: 12) {
                MiloAvatar(size: 88)
                VStack(alignment: .leading, spacing: 5) {
                    Text("嗨，我是 \(MiloPersona(name: miloName).name)").font(.title3.weight(.semibold))
                    Text("让训练融入日常。").font(.subheadline).foregroundStyle(Theme.Journal.secondary)
                }
            }.padding(.horizontal, 22).padding(.vertical, 15)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.stage == .selection ? "连接你的日常" : model.stage == .progress ? "正在连接" : "开始新日常")
                        .font(.title2.weight(.semibold))
                    Spacer(minLength: 10)
                    Button(model.stage == .result ? "稍后处理" : "稍后再说", action: finish)
                        .font(.caption).foregroundStyle(Theme.Journal.secondary).frame(minHeight: 44)
                        .disabled(model.busy)
                }.padding(.horizontal, 22).padding(.top, 16)
                if model.stage == .selection {
                    Text("选好服务，接下来跟着系统提示允许。")
                        .font(.footnote).foregroundStyle(Theme.Journal.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            switch model.stage {
                            case .selection: selection
                            case .progress: progress
                            case .result: result
                            }
                            if model.stage != .progress { settings.id("calendar-options") }
                            if let error = model.error {
                                Text(error).font(.footnote).foregroundStyle(Theme.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("连接提示：\(error)")
                            }
                        }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)
                    }
                    .onChange(of: model.calendarNeedsSetup) { _, needed in
                        if needed {
                            details = true
                            Task { @MainActor in
                                await Task.yield()
                                withAnimation { proxy.scrollTo("calendar-options", anchor: .top) }
                            }
                        }
                    }
                    .onChange(of: details) { _, expanded in
                        if expanded {
                            Task { @MainActor in
                                await Task.yield()
                                withAnimation { proxy.scrollTo("calendar-options", anchor: .top) }
                            }
                        }
                    }
                }
                footer
            }
            .background(Theme.Journal.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        }
        .foregroundStyle(Theme.Journal.label)
        .background(Theme.Journal.panel.ignoresSafeArea())
        .navigationTitle(onboarding ? "" : "连接服务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(onboarding ? .hidden : .visible, for: .navigationBar)
        .task { model.load(context: context, onboarding: onboarding) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.pause() }
            else if phase == .active { model.refresh() }
        }
        .onReceive(calendar.$revision) { _ in model.refresh() }
        .onDisappear { model.pause() }
    }

    private var selection: some View {
        VStack(spacing: 9) {
            HStack {
                Text("按需选择，随时可调整")
                Spacer()
                Text("已选 \(model.selected.count) 项")
            }.font(.caption).foregroundStyle(Theme.Journal.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ServiceConnectionTarget.allCases) { target in
                    let selected = model.selected.contains(target)
                    Button { model.toggle(target) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                serviceIcon(target)
                                Spacer(minLength: 4)
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18)).foregroundStyle(selected ? Theme.accent : Theme.Journal.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title).font(.subheadline.weight(.medium))
                                Text(tileHint(target)).font(.caption2).foregroundStyle(Theme.Journal.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading).padding(12)
                        .background(selected ? Theme.Journal.panel : Theme.Journal.canvas,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.Journal.action.opacity(0.6) : Theme.Journal.line, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.loaded || model.busy || (model.access(target) == .unavailable && !selected) || (model.access(target) == .restricted && !selected))
                    .accessibilityLabel("\(target.title)，\(target.purpose)")
                    .accessibilityValue(selected ? "已选择" : "未选择")
                }
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 16) {
            VStack(spacing: 11) {
                serviceIcon(model.flow.current ?? model.targets.first ?? .calendar, size: 56)
                Text("正在连接\((model.flow.current ?? model.targets.first)?.title ?? "服务")").font(.headline)
                Text("在系统弹窗中选择是否允许。").font(.footnote).foregroundStyle(Theme.Journal.secondary)
                ProgressView(value: Double(processed), total: Double(max(1, model.targets.count))).tint(Theme.accent)
                Text("\(processed) / \(model.targets.count) 项已处理").font(.caption2)
                    .foregroundStyle(Theme.Journal.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(18).frame(maxWidth: .infinity).background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: 19))
            connectionRows
        }
    }

    private var processed: Int {
        model.targets.filter { if case .some(.checked(_)) = model.flow.steps[$0] { return true }; if case .some(.failed(_)) = model.flow.steps[$0] { return true }; return false }.count
    }

    private var result: some View {
        VStack(spacing: 16) {
            VStack(spacing: 13) {
                HStack(spacing: -5) { ForEach(Array(model.complete.prefix(4))) { serviceIcon($0, size: 42) } }
                    .accessibilityHidden(true)
                Text(model.complete.isEmpty ? "稍后也能继续" : "\(model.complete.count) 项连接已完成")
                    .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(model.pending.isEmpty ? "准备好了，开始你的训练日常吧。" : "已完成的可以先用，其余服务随时补连。")
                    .font(.subheadline).foregroundStyle(Theme.Journal.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 16)
            if !model.pending.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.pending) { target in
                        HStack(spacing: 10) {
                            serviceIcon(target)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(target.title).font(.subheadline.weight(.medium))
                                Text(model.status(target)).font(.caption).foregroundStyle(Theme.Journal.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            pendingAction(target)
                        }.padding(.vertical, 11)
                    }
                }.padding(.horizontal, 13).background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: 15))
            }
            DisclosureGroup("查看连接详情", isExpanded: $resultDetails) {
                connectionRows
                Text("健康数据按系统中实际允许的范围读取；音乐播放取决于订阅与可播放内容。")
                    .font(.caption).foregroundStyle(Theme.Journal.secondary)
            }.font(.footnote).tint(Theme.Journal.secondary)
            Button("调整服务选择") { model.edit() }.font(.footnote).foregroundStyle(Theme.Journal.secondary).frame(minHeight: 44)
        }
    }

    @ViewBuilder private func pendingAction(_ target: ServiceConnectionTarget) -> some View {
        let access = model.access(target)
        if access == .denied {
            Button("去设置") { openSettings() }.font(.caption).frame(minWidth: 44, minHeight: 44)
        } else if access == .needsCalendarSelection {
            Button("选择") { details = true }.font(.caption).frame(minWidth: 44, minHeight: 44)
        } else if access.needsRequest {
            Button("继续") { model.start() }.font(.caption).frame(minWidth: 44, minHeight: 44).disabled(model.busy)
        }
    }

    private var connectionRows: some View {
        VStack(spacing: 0) {
            ForEach(model.targets) { target in
                HStack(spacing: 10) {
                    Image(systemName: target.symbol).frame(width: 23).foregroundStyle(Theme.Journal.secondary)
                    Text(target.title).font(.subheadline)
                    Spacer(minLength: 8)
                    Text(model.status(target)).font(.caption).foregroundStyle(Theme.Journal.secondary).multilineTextAlignment(.trailing)
                }.padding(.vertical, 11)
                Divider().overlay(Theme.Journal.line)
            }
        }
    }

    private var settings: some View {
        DisclosureGroup(model.stage == .result ? "更多设置" : "连接设置", isExpanded: $details) {
            VStack(alignment: .leading, spacing: 14) {
                if model.selected.contains(.calendar) {
                    Text("允许查询的日历").font(.subheadline.weight(.medium))
                    if calendar.fullAccess {
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                            Toggle(item.title, isOn: Binding(get: { model.config.calendarIDs.contains(item.calendarIdentifier) }, set: { enabled in
                                model.update { value in
                                    value.calendarIDs.removeAll { $0 == item.calendarIdentifier }
                                    if enabled { value.calendarIDs.append(item.calendarIdentifier) }
                                }
                            })).font(.subheadline)
                        }
                        Picker("默认写入日历", selection: preference(\.writeCalendarID)) {
                            Text("请选择").tag("")
                            if !model.config.writeCalendarID.isEmpty,
                               calendar.store.calendar(withIdentifier: model.config.writeCalendarID)?.allowsContentModifications != true {
                                Text("原日历已失效，请重选").tag(model.config.writeCalendarID)
                            }
                            ForEach(calendar.calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) {
                                Text($0.title).tag($0.calendarIdentifier)
                            }
                        }.font(.subheadline)
                        if model.config.calendarIDs.contains(where: { calendar.store.calendar(withIdentifier: $0) == nil }) {
                            Text("部分已选日历已失效，请重新选择。")
                            Button("移除失效选择") { model.update { value in value.calendarIDs.removeAll { calendar.store.calendar(withIdentifier: $0) == nil } } }
                        }
                    } else { Text("连接日历后，再选择允许查询的范围。") }
                }
                Toggle("确认训练时同步关联日历", isOn: preference(\.syncTrainingCalendar))
                    .disabled(!model.config.enabled.contains(.calendar))
                Toggle("确认训练时安排关联闹钟", isOn: preference(\.syncTrainingAlarms))
                    .disabled(!model.config.enabled.contains(.alarms))
                Stepper("提前 \(model.config.reminderMinutes) 分钟提醒", value: preference(\.reminderMinutes), in: 0...120, step: 5)
                NavigationLink("选择训练音乐") { CoachMusicView().toolbar(.visible, for: .navigationBar) }
                NavigationLink("Siri 与快捷指令") { CoachSiriSettingsView().toolbar(.visible, for: .navigationBar) }
                Button("前往系统设置", action: openSettings)
                Text("连接不会自动创建日程或闹钟。关闭连接保留已有记录与系统提醒；地图不允许定位仍可手填地点。自动调整继续遵守你保存的规则。")
                    .font(.caption).foregroundStyle(Theme.Journal.secondary)
            }.font(.footnote).padding(.top, 8).disabled(model.busy)
        }.font(.footnote).tint(Theme.Journal.secondary).disabled(!model.loaded || model.busy)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                if model.flow.isRunning { model.pause() }
                else if model.stage == .result { finish() }
                else { model.start() }
            } label: {
                HStack(spacing: 10) {
                    Text(model.flow.isRunning ? "暂停后续连接" : model.stage == .result ? "开始使用" : model.selected.isEmpty && !onboarding ? "保存选择" : "连接所选服务")
                    if !model.flow.isRunning { Image(systemName: "arrow.right").font(.footnote) }
                }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                    .background(model.flow.isRunning ? Theme.Journal.panel : Theme.accent, in: Capsule())
                    .foregroundStyle(model.flow.isRunning ? Theme.Journal.label : Theme.onAccent)
            }.buttonStyle(.plain)
                .disabled(!model.loaded || (!model.flow.isRunning && model.busy) || (onboarding && model.stage == .selection && model.selected.isEmpty))
            Text(model.flow.isRunning ? "暂停不会撤回已授予的系统权限。" : model.stage == .result ? "之后仍可在设置中调整连接。" : "系统弹窗需要逐项确认。")
                .font(.caption2).foregroundStyle(Theme.Journal.secondary).multilineTextAlignment(.center)
        }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 14)
    }

    private func preference<T>(_ key: WritableKeyPath<CoachPluginConfiguration, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: key] }, set: { value in model.update { $0[keyPath: key] = value } })
    }
    private func finish() { if model.finish() { if let onFinish { onFinish() } else { dismiss() } } }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
    private func tileHint(_ target: ServiceConnectionTarget) -> String {
        let access = model.access(target)
        return access == .unavailable || access == .restricted || access == .denied ? model.status(target) : target.purpose
    }
    private func serviceIcon(_ target: ServiceConnectionTarget, size: CGFloat = 32) -> some View {
        Image(systemName: target.symbol).font(.system(size: size * 0.56, weight: .medium))
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(target.color, in: RoundedRectangle(cornerRadius: size * 0.3)).accessibilityHidden(true)
    }
}

private extension ServiceConnectionTarget {
    var title: String { self == .health ? "健康" : plugin?.title ?? rawValue }
    var symbol: String { self == .health ? "heart" : plugin?.symbol ?? "link" }
    var purpose: String {
        switch self {
        case .health: return "只读睡眠与运动摘要"
        case .calendar: return "安排训练时间"
        case .alarms: return "训练前提醒"
        case .music: return "训练时播放"
        case .maps: return "使用期间定位，附近与路线"
        case .browser: return "查资料，由你确认网页"
        }
    }
    var color: Color {
        switch self {
        case .health: return Color(red: 0.91, green: 0.46, blue: 0.47)
        case .calendar: return Color(red: 0.39, green: 0.55, blue: 0.51)
        case .alarms: return Color(red: 0.77, green: 0.61, blue: 0.32)
        case .music: return Color(red: 0.74, green: 0.48, blue: 0.57)
        case .maps: return Color(red: 0.49, green: 0.61, blue: 0.45)
        case .browser: return Color(red: 0.45, green: 0.60, blue: 0.71)
        }
    }
}
