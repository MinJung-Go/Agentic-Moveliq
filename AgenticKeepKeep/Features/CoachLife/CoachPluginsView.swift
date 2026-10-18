import SwiftData
import SwiftUI

struct CoachPluginsView: View {
    var body: some View { ServiceConnectionView() }
}

@MainActor
struct CoachMusicView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var music = MusicPluginService.shared
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    @State private var token: String?
    @Query(sort: [SortDescriptor(\CoachActionRecord.date, order: .reverse)]) private var actions: [CoachActionRecord]
    var body: some View {
        List {
            Section {
                Text(music.currentTitle).font(.headline)
                HStack {
                    Button("上一首", systemImage: "backward.end.fill") { control("previous") }
                    Button(music.playing ? "暂停" : "继续", systemImage: music.playing ? "pause.fill" : "play.fill") { control(music.playing ? "pause" : "resume") }
                    Button("下一首", systemImage: "forward.end.fill") { control("next") }
                }.buttonStyle(.borderless).disabled(busy)
            }
            Section("选择歌曲、专辑或歌单") {
                TextField("歌名、歌手或歌单", text: $query).submitLabel(.search).onSubmit { search() }
                Button(busy ? "正在查询…" : "搜索") { search() }.disabled(busy || query.isEmpty)
                if !music.notice.isEmpty { Text(music.notice).font(.caption).foregroundStyle(Theme.secondaryLabel) }
                ForEach(music.choices) { item in
                    Button {
                        do {
                            try require()
                            _ = try CoachLifeStore.action(kind: "music", payload: CoachActionPayload(musicID: item.id, musicKind: item.kind, title: item.title, reason: "替换 Apple 音乐当前播放队列。"), in: context)
                        } catch { self.error = error.localizedDescription }
                    } label: { VStack(alignment: .leading) { Text(item.title); Text("\(item.kind) · \(item.subtitle)").font(.caption).foregroundStyle(Theme.secondaryLabel) } }
                }
            }
            ForEach(actions.filter { $0.kind == "music" && ["pending", "partial", "executing"].contains($0.state) }.prefix(3), id: \.uuid) { CoachPluginActionCard(action: $0) }
            if let error { Text(error).foregroundStyle(Theme.danger).font(.footnote) }
        }.navigationTitle("Apple 音乐").task { token = ServiceCredentials.session?.token }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in music.refreshPlayback() }
    }
    private func require() throws { try CoachLifeStore.require(.music, context: context, token: token) }
    private func search() {
        guard !busy else { return }; busy = true; error = nil
        Task { defer { busy = false }; do { try require(); _ = try await music.search(query, revalidate: require) } catch { self.error = "音乐查询失败：\(error.localizedDescription)" } }
    }
    private func control(_ action: String) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { _ = try await music.control(action, revalidate: require) } catch { self.error = error.localizedDescription } }
    }
}

@MainActor
struct CoachSiriSettingsView: View {
    var body: some View {
        List {
            Section { Text("用一句话打开 Moveliq。系统可能要求先解锁；记录仍需在 App 内确认保存。") }
            Section("可以这样说") {
                Label("用 Moveliq 打开 Milo", systemImage: "bubble.left")
                Label("用 Moveliq 查看今日训练", systemImage: "calendar")
                Label("用 Moveliq 记一笔", systemImage: "square.and.pencil")
            }
            Link("打开快捷指令", destination: URL(string: "shortcuts://")!)
        }.navigationTitle("Siri 与快捷指令")
    }
}
