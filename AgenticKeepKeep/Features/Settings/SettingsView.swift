import SwiftUI
import SwiftData

/// 设置：账号、云端 AI、健康数据、用量、关于
struct SettingsView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = LLMSettings.shared
    @ObservedObject private var health = HealthKitService.shared

    @AppStorage(MiloPersona.nameKey) private var miloName = "Milo"
    private var displayName: String { MiloPersona(name: miloName).name }

    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isSyncingHealth = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private enum Page: String, Hashable {
        case model = "AI 模型"
        case health = "Apple 健康"
        case data = "数据管理"
        case usage = "用量统计"
        case about = "关于 Moveliq"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        BrandMark(size: 40)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Moveliq").font(Theme.Font.headline)
                            Text("自己的训练，自己掌握")
                                .font(Theme.Font.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                Section {
                    NavigationLink { AccountSettingsView() } label: {
                        SettingsRowLabel(title: "账号与邀请码", symbol: "person.crop.circle")
                    }
                    NavigationLink { MiloSettingsView() } label: {
                        SettingsRowLabel(title: "\(displayName) · 相处方式", symbol: "person.crop.circle")
                    }
                    settingsLink(.model, symbol: "cpu", detail: "云端服务")
                    settingsLink(.health, symbol: "heart", detail: healthSummary)
                }
                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        SettingsRowLabel(title: "外观", symbol: "circle.lefthalf.filled")
                    }
                }
                Section {
                    settingsLink(.data, symbol: "externaldrive", detail: nil)
                    settingsLink(.usage, symbol: "chart.bar", detail: nil)
                }
                Section {
                    settingsLink(.about, symbol: "info.circle", detail: nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .navigationTitle("设置")
            .navigationDestination(for: Page.self) { page in
                Form {
                    switch page {
                    case .model:
                        llmSection
                        searchSection
                    case .health: healthSection
                    case .data: backupSection
                    case .usage: usageSection
                    case .about:
                        aboutSection
                    }
                }
                .navigationTitle(page.rawValue)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var healthSummary: String {
        switch health.authorizationState {
        case .notRequested: return "待授权"
        case .unsupportedSigning, .failed: return "需处理"
        case .unavailable: return "不可用"
        case .requested: return "已请求授权"
        }
    }

    private func settingsLink(_ page: Page, symbol: String, detail: String?) -> some View {
        NavigationLink(value: page) {
            SettingsRowLabel(title: page.rawValue, symbol: symbol, detail: detail)
        }
    }

    // MARK: - AI 模型

    private var searchSection: some View {
        Section {
            Toggle("允许 \(displayName) 联网搜索", isOn: $settings.webSearchEnabled)
                .disabled(!settings.supportsWebSearch)
        } footer: {
            Text(settings.supportsWebSearch ? "公共主题词通过 Moveliq 服务查询，不附带个人记录。" : "管理员尚未开启联网检索。")
        }
    }

    private var llmSection: some View {
        Section {
            LabeledContent("AI 服务", value: "Moveliq 云端服务")
            Toggle("深度思考", isOn: $settings.thinkingEnabled)
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    if isTesting { ProgressView() }
                    Text(isTesting ? "测试中…" : "连接测试")
                }
            }.disabled(isTesting || !settings.isConfigured)
            switch testResult {
            case .success(let message): Text(message).font(.footnote).foregroundStyle(Theme.positive)
            case .failure(let message): Text(message).font(.footnote).foregroundStyle(Theme.danger)
            case nil: EmptyView()
            }
        } footer: {
            Text("登录凭据保存在系统钥匙串。输入的文本、识别照片和相关摘要经 Moveliq 服务转交模型处理；模型密钥只保存在服务端。")
        }
    }

    // MARK: - 数据

    private var healthSection: some View {
        Section {
            LabeledContent {
                Text(health.authorizationState.title)
                    .foregroundStyle(Theme.secondaryLabel)
            } label: {
                Label("HealthKit", systemImage: "heart.text.square.fill")
            }

            if let status = health.statusMessage {
                Text(status)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(health.isSigningUnsupported ? Theme.warning : Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if health.authorizationState != .unavailable {
                Button {
                    Task { await authorizeAndSync() }
                } label: {
                    if isSyncingHealth {
                        HStack {
                            ProgressView()
                            Text("同步中…")
                        }
                    } else {
                        Text(health.authorizationActionTitle)
                    }
                }
                .disabled(isSyncingHealth || health.isAuthorizing || health.isSyncing)
            }

            if let last = health.lastSyncDate {
                LabeledContent {
                    Text(Format.shortDay(last) + " " + Format.time(last))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryLabel)
                } label: {
                    Label("上次同步", systemImage: "clock.arrow.circlepath")
                }
            }

        } header: {
            Text("健康数据同步")
        } footer: {
            Text("读取已允许的运动、步数、活动能量与恢复数据。授权或同步失败时，可在这里重试。")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                exportData()
            } label: {
                Label("导出我的数据（JSON）", systemImage: "square.and.arrow.up")
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("分享导出文件", systemImage: "doc.text")
                }
            }

            if let exportError {
                Text(exportError)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
            }
        } header: {
            Text("数据")
        }
    }

    // MARK: - 用量

    /// 输入 / 输出占比条。两段是**同色相深浅**，不是两个色相 —— 它们是同一个量的两部分
    private var usageBar: some View {
        let prompt = Double(settings.usage.promptTokens)
        let completion = Double(settings.usage.completionTokens)
        let total = max(1, prompt + completion)

        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(ChartColor.training)
                        .frame(width: max(0, proxy.size.width * prompt / total - 1))
                    Capsule()
                        .fill(ChartColor.training.opacity(ChartColor.medium))
                }
            }
            .frame(height: 6)

            HStack(spacing: Theme.Spacing.m) {
                legend(color: ChartColor.training, label: "输入", value: settings.usage.promptTokens)
                legend(
                    color: ChartColor.training.opacity(ChartColor.medium),
                    label: "输出",
                    value: settings.usage.completionTokens
                )
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func legend(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(Theme.Font.badge)
                .fontWeight(.regular)
                .foregroundStyle(Theme.secondaryLabel)
            Text("\(value)")
                .font(Theme.Font.badge)
                .fontWeight(.regular)
                .foregroundStyle(Theme.tertiaryLabel)
                .monospacedDigit()
        }
    }

    private var usageSection: some View {
        Section {
            LabeledContent {
                Text("\(settings.usage.totalTokens)")
                    .monospacedDigit()
            } label: {
                Label("Token 消耗", systemImage: "number")
            }

            usageBar

            LabeledContent {
                Text("\(settings.callCount) 次")
                    .monospacedDigit()
            } label: {
                Label("Agent 调用", systemImage: "arrow.triangle.2.circlepath")
            }

            Button("重置统计", role: .destructive) {
                settings.resetUsage()
                Haptics.warning()
            }
        } header: {
            Text("累计用量")
        } footer: {
            Text("统计只存在本机，用于估算自己的用量。")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(appVersion).foregroundStyle(Theme.secondaryLabel).monospacedDigit()
            } label: {
                Label("版本", systemImage: "info.circle")
            }

            Link(destination: URL(string: "https://github.com/MinJung-Go/Agentic-KeepKeep")!) {
                LabeledContent {
                    Text("MIT").foregroundStyle(Theme.secondaryLabel)
                } label: {
                    Label("GitHub 开源", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            NavigationLink {
                PrivacyInfoView()
            } label: {
                Label("架构与隐私说明", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("关于")
        } footer: {
            Text("Moveliq · MIT License · 本地优先的健身记录与分析")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - 动作

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        let result = await settings.testConnection()
        switch result {
        case .success(let message):
            testResult = .success(message)
            Haptics.success()
        case .failure(let error):
            testResult = .failure(error.localizedDescription)
            Haptics.warning()
        }
    }

    private func authorizeAndSync() async {
        isSyncingHealth = true
        defer { isSyncingHealth = false }

        if await health.authorizeAndSync(into: context) {
            appState.showToast("同步完成，仅导入已允许读取的数据")
        }
    }

    private func exportData() {
        exportError = nil
        do {
            exportURL = try DataExporter.exportFile(context: context)
            appState.showToast("导出文件已生成")
        } catch {
            exportError = "导出失败：\(error.localizedDescription)"
        }
    }
}

/// 隐私说明：把架构约定**逐条**写给用户看。
/// 用「图标 + 一句话」的条目，而不是几段连续文字 —— 前者能扫，后者只能读。
struct PrivacyInfoView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @State private var exportURL: URL?
    @State private var exportError: String?

    private struct PrivacyItem: Identifiable {
        let id = UUID()
        let symbol: String
        let tint: Color
        let text: String
    }

    private struct PrivacyGroup: Identifiable {
        let id = UUID()
        let title: String
        let note: String?
        let items: [PrivacyItem]
    }

    private let groups: [PrivacyGroup] = [
        PrivacyGroup(
            title: "留在本机",
            note: "账号与邀请关系保存在 Moveliq 服务端；训练与饮食记录不做云同步。",
            items: [
                PrivacyItem(symbol: "internaldrive.fill", tint: Theme.info, text: "训练、饮食、身体指标、笔记全部存在本机 SwiftData 数据库"),
                PrivacyItem(symbol: "heart.fill", tint: Theme.danger, text: "HealthKit 数据只读读取：睡眠、HRV、静息心率、步数、运动记录，**不回写**"),
                PrivacyItem(symbol: "key.fill", tint: Theme.accent, text: "登录凭据存在系统钥匙串；模型 API Key 只保存在服务端"),
            ]
        ),
        PrivacyGroup(
            title: "会离开设备",
            note: "AI 请求经 Moveliq 服务中转到模型供应商。",
            items: [
                PrivacyItem(symbol: "text.bubble.fill", tint: Theme.accent, text: "你输入的文本及对话内容，经 Moveliq 服务转交模型处理"),
                PrivacyItem(symbol: "video.fill", tint: Theme.accent, text: "实时通话音频及主动开启摄像头后的画面经服务转交模型，App 不保存原音视频，文字留在聊天中"),
                PrivacyItem(symbol: "mic.fill", tint: Theme.accent, text: "语音优先在设备上识别，不支持时可能使用 Apple 服务；原音频不保存，转写文字按聊天内容处理"),
                PrivacyItem(symbol: "chart.bar.doc.horizontal.fill", tint: Theme.positive, text: "聚合后的统计摘要，例如「近 7 天训练 4 次、日均睡眠 6.2 小时、深蹲停滞 3 周」"),
                PrivacyItem(symbol: "photo.fill", tint: Theme.secondaryLabel, text: "主动选择识别的照片以压缩图发送，原图留在本机"),
            ]
        ),
        PrivacyGroup(
            title: "不会离开设备",
            note: nil,
            items: [
                PrivacyItem(symbol: "list.bullet.rectangle", tint: Theme.secondaryLabel, text: "逐条训练与饮食明细 —— 摘要之外的原始记录一律不出设备"),
            ]
        ),
        PrivacyGroup(
            title: "你随时可以带走",
            note: nil,
            items: [
                PrivacyItem(symbol: "square.and.arrow.up.fill", tint: Theme.accent, text: "全部数据可导出为 JSON 文件，自己留存或迁移"),
            ]
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeader(text: group.title)

                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            if let note = group.note {
                                Text(note)
                                    .font(Theme.Font.footnote)
                                    .foregroundStyle(Theme.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(group.items) { item in
                                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                    Image(systemName: item.symbol)
                                        .font(.system(size: 14, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(item.tint)
                                        .frame(width: 20)
                                    Text(LocalizedStringKey(item.text))
                                        .font(Theme.Font.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .card()
                    }
                }

                exportCard
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.canvas)
        .navigationTitle("架构与隐私")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("导出全部数据")
                .font(Theme.Font.subheadline.weight(.semibold))
            Text("生成一个 JSON 文件，包含所有训练、饮食、指标与笔记。")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            if let exportURL {
                ShareLink(item: exportURL) {
                    Text("分享导出文件")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("生成导出文件") { export() }
                    .buttonStyle(PrimaryButtonStyle())
            }

            if let exportError {
                Text(exportError)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private func export() {
        exportError = nil
        do {
            exportURL = try DataExporter.exportFile(context: context)
            Haptics.success()
            appState.showToast("导出文件已生成")
        } catch {
            exportError = "导出失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .modelContainer(try! AppModelContainer.inMemory())
}

/// All root settings rows share the same icon column, typography and title inset.
private struct SettingsRowLabel: View {
    let title: String
    let symbol: String
    var detail: String? = nil

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    private let spacing: CGFloat = 12

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            if let detail {
                Spacer(minLength: Theme.Spacing.s)
                Text(detail)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + iconWidth + spacing
        }
    }
}
