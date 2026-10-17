import SwiftData
import SwiftUI
import UIKit

@MainActor
struct CoachPluginsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var calendar = CalendarPluginService.shared
    @ObservedObject private var maps = MapsPluginService.shared
    @ObservedObject private var music = MusicPluginService.shared
    @State private var config = CoachPluginConfiguration()
    @State private var token: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var authRevision = UUID()
    var body: some View {
        Form {
            Section {
                Text("按需连接，随时关闭。插件开关按当前账号保存，系统授权单独管理。")
                    .font(.subheadline).foregroundStyle(Theme.secondaryLabel)
                ForEach(CoachPlugin.allCases) { plugin in
                    Toggle(isOn: Binding(get: { config.enabled.contains(plugin) }, set: { enabled in
                        var copy = config
                        if enabled { copy.enabled.insert(plugin) } else { copy.enabled.remove(plugin) }
                        commit(copy)
                    })) { Label(plugin.title, systemImage: plugin.symbol) }
                    .disabled(!loaded || busy || (plugin == .alarms && !AlarmPluginService.available))
                }
            } footer: { Text("关闭插件不会删除系统已保存的日程和闹钟，也不会清空音乐队列。") }
            calendarSection
            Section("地图") {
                Text(maps.locationStatus).font(.footnote)
                Button("允许查询附近地点时使用位置") { maps.authorize() }
                Text("不授权也可提供地点名称。只请求使用期间定位，不在后台跟踪。")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
            }
            Section("闹钟") {
                Text(AlarmPluginService.status).id(authRevision)
                Button("允许闹钟提醒") { authorize { try await AlarmPluginService.authorize() } }
                    .disabled(!AlarmPluginService.available || busy)
                Toggle("确认训练时安排关联闹钟", isOn: preference(\.syncTrainingAlarms))
                    .disabled(!config.enabled.contains(.alarms))
                Text("管理 Moveliq 创建的闹钟。‘N分钟后提醒’以一次性系统闹钟实现，不提供后台常驻计时。")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
            }
            Section("Apple 音乐") {
                Text(music.status)
                Button("连接 Apple 音乐") { authorize { await music.authorize() } }.disabled(busy)
                NavigationLink("选择训练音乐") { CoachMusicView() }
                Text("曲库播放取决于订阅、地区及安装版本的音乐服务配置；未订阅时查询可用媒体库。")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
            }
            Section("系统入口") { NavigationLink("Siri 与快捷指令") { CoachSiriSettingsView() } }
            Section { Button("前往系统设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
            if let error { Section { Text(error).foregroundStyle(Theme.danger).font(.footnote) } }
        }
        .navigationTitle("插件").navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { authRevision = UUID(); load() } }
    }
    private var calendarSection: some View {
        Section {
            Text(calendar.status)
            Button("连接系统日历（完整访问）") { authorize { try await calendar.authorize() } }.disabled(busy)
            if calendar.fullAccess {
                ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                    Toggle(item.title, isOn: Binding(get: { config.calendarIDs.contains(item.calendarIdentifier) }, set: { selected in
                        var copy = config; copy.calendarIDs.removeAll { $0 == item.calendarIdentifier }
                        if selected { copy.calendarIDs.append(item.calendarIdentifier) }; commit(copy)
                    }))
                }
                Picker("默认写入日历", selection: preference(\.writeCalendarID)) {
                    Text("请选择").tag("")
                    ForEach(calendar.calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                }
            }
            Toggle("确认训练时同步关联日历", isOn: preference(\.syncTrainingCalendar))
                .disabled(!config.enabled.contains(.calendar))
            Stepper("提前 \(config.reminderMinutes) 分钟提醒", value: preference(\.reminderMinutes), in: 0...120, step: 5)
        } header: { Text("日历 · 选择允许查询的范围") } footer: {
            Text("查询与管理需要完整访问。只把完成当前规划需要的忙闲/日程摘要给教练，备注、参会人和会议链接保留本机。只有添加权限时无法查询或改期。")
        }
    }
    private func preference<T>(_ path: WritableKeyPath<CoachPluginConfiguration, T>) -> Binding<T> {
        Binding(get: { config[keyPath: path] }, set: { value in var copy = config; copy[keyPath: path] = value; commit(copy) })
    }
    private func commit(_ value: CoachPluginConfiguration) {
        do { try CoachLifeStore.checkAccount(context: context, token: token); try CoachLifeStore.save(plugins: value, in: context); config = value; error = nil }
        catch { self.error = "设置未保存：\(error.localizedDescription)" }
    }
    private func load() {
        do { config = try CoachLifeStore.plugins(context); token = ServiceCredentials.session?.token; loaded = true }
        catch { error = error.localizedDescription }
    }
    private func authorize(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; let marker = token
        Task { @MainActor in
            defer { busy = false; authRevision = UUID() }
            do { try CoachLifeStore.checkAccount(context: context, token: marker); try await operation(); try CoachLifeStore.checkAccount(context: context, token: marker) }
            catch { self.error = error.localizedDescription }
        }
    }
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
