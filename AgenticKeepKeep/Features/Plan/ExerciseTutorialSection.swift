import SwiftUI
import SwiftData

struct ExerciseTutorialSection: View {
    let name: String
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = ExerciseTutorialStore.shared
    @ObservedObject private var settings = LLMSettings.shared
    @Query private var cache: [ExerciseTutorialCache]
    @State private var showsAlternatives = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?

    private var key: String? { TutorialExercise.resolve(name)?.name }
    private var entry: ExerciseTutorialCache? { cache.first { $0.key == key } }
    private var videos: [ExerciseTutorial] { ExerciseTutorialStore.entries(entry) }
    private var loading: Bool { key.map { store.running.contains($0) } ?? false }
    private var enabled: Bool { !settings.useLocalModel && settings.webSearchEnabled && settings.supportsWebSearch && settings.isConfigured }

    var body: some View {
        Section {
            let activities = key.flatMap { store.activities[$0] } ?? CoachToolActivity.decode(entry?.activityJSON)
            if !activities.isEmpty { CoachToolActivityView(activities: activities, initiallyExpanded: loading) }
            if let video = videos.first {
                videoCard(video)
                HStack {
                    Button("换一个 / 查看备选") { showsAlternatives = true }
                    Spacer()
                    Button("链接失效？") {
                        guard let entry else { return }
                        do { try ExerciseTutorialStore.reject(video, entry: entry, context: context) }
                        catch { self.error = "反馈保存失败，请重试" }
                    }
                }.font(.footnote).buttonStyle(.borderless)
            }
            if loading {
                HStack { ProgressView(); Text("正在寻找合适的教学…").font(.footnote) }
                Button("停止补充") { store.stop(name: name) }
            } else if videos.isEmpty {
                Text(emptyMessage).font(.footnote).foregroundStyle(.secondary)
                if enabled, key != nil { Button("查找教学视频") { search() } }
                if !enabled { NavigationLink("前往模型与联网设置") { SettingsView() } }
            }
            if let message = error ?? store.error { Text(message).font(.footnote).foregroundStyle(Theme.danger) }
        } header: { Text("动作教学") } footer: {
            Text("仅根据公开标题与页面介绍筛选，未审核完整视频。跳转原站观看，不下载视频。")
        }
        .sheet(isPresented: $showsAlternatives) {
            NavigationStack {
                List {
            Group {
                    ForEach(videos) { video in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(video.title).font(.headline)
                            Text("\(video.author ?? "作者未提供") · \(video.platform)").font(.footnote).foregroundStyle(.secondary)
                            Text(video.reason).font(.footnote)
                            HStack {
                                Button("用这个") {
                                    guard let entry else { return }
                                    do {
                                        try ExerciseTutorialStore.choose(video, entry: entry, context: context)
                                        showsAlternatives = false
                                    } catch { self.error = "选择保存失败，请重试" }
                                }
                                Spacer()
                                Button("先看看 ↗") { open(video) }
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 8)
                    }
                    if videos.isEmpty { Text("暂无可用备选") }
                    if enabled {
                        Button(loading ? "正在查找…" : "重新查找") { search() }.disabled(loading)
                    }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
                .navigationTitle("教学视频")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsAlternatives = false } } }
            }
        }
    }
    private var emptyMessage: String {
        if settings.useLocalModel { return "本机模式可在 Milo 对话中查阅公开资料；教学视频自动补充暂不支持。" }
        if key == nil { return "暂无合适视频。动作名称或器械变式暂未匹配，不影响训练。" }
        if !settings.webSearchEnabled { return "联网搜索已关闭，已有课程仍可使用。" }
        if !enabled { return "请先配置智谱官方模型与联网搜索。" }
        if entry?.status == "failed" { return "这次未能完成查询，请稍后重试。" }
        if entry?.status == "stopped" { return "已停止补充，课程已保留。" }
        return entry == nil ? "课程已就绪，教学可以随后补充。" : "暂无合适视频，未找到可靠匹配。"
    }
    private func search() {
        request?.cancel()
        request = Task { await store.load(name: name, context: context) }
    }
    private func open(_ video: ExerciseTutorial) {
        guard ExerciseTutorial.platform(for: video.url) != nil else { return }
        openURL(video.url) { accepted in if !accepted { error = "无法打开链接，请尝试其他来源" } }
    }
    private func videoCard(_ video: ExerciseTutorial) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(video.platform == "哔哩哔哩" ? "中文来源优先" : "补充来源").font(.caption).foregroundStyle(Theme.accent)
            Text(video.title).font(.headline)
            Text("\(video.author ?? "作者未提供") · \(video.platform)").font(.footnote).foregroundStyle(.secondary)
            Text(video.reason).font(.footnote).foregroundStyle(.secondary)
            Button { open(video) } label: {
                Label("查看教学", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
        }.padding(.vertical, 8)
    }
}
