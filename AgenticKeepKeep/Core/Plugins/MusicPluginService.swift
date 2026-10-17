import Combine
import Foundation
import MusicKit

@MainActor
final class MusicPluginService: ObservableObject {
    static let shared = MusicPluginService()
    struct Choice: Identifiable {
        var id: String
        var title: String
        var subtitle: String
        var kind: String
    }
    private enum Item { case song(Song), album(Album), playlist(Playlist) }
    @Published private(set) var choices: [Choice] = []
    @Published private(set) var notice = ""
    @Published private(set) var revision = UUID()
    private var items: [String: Item] = [:]
    private var generation = UUID()
    var authorized: Bool { MusicAuthorization.currentStatus == .authorized }
    var status: String {
        switch MusicAuthorization.currentStatus {
        case .authorized: return "已授权"
        case .notDetermined: return "尚未授权"
        case .denied: return "访问被拒绝"
        case .restricted: return "访问受限制"
        @unknown default: return "暂不可用"
        }
    }
    var currentTitle: String { authorized ? (SystemMusicPlayer.shared.queue.currentEntry?.title ?? "当前没有曲目") : "尚未连接音乐" }
    var playing: Bool { authorized && SystemMusicPlayer.shared.state.playbackStatus == .playing }
    func authorize() async { _ = await MusicAuthorization.request(); revision = UUID() }
    func reset() { generation = UUID(); choices = []; items = [:]; notice = "" }
    func refreshPlayback() { if authorized { revision = UUID() } }
    func search(_ text: String, revalidate: () throws -> Void) async throws -> [Choice] {
        guard authorized else { throw CoachPluginError.unavailable("请先在插件设置中授权 Apple 音乐。") }
        guard !text.isEmpty, text.count <= 200 else { throw CoachPluginError.invalid }
        let marker = generation
        var found: [Choice] = [], cache: [String: Item] = [:]
        func add(_ item: Item, title: String, subtitle: String, kind: String) {
            let token = UUID().uuidString
            found.append(Choice(id: token, title: title, subtitle: subtitle, kind: kind)); cache[token] = item
        }
        let subscription = try? await MusicSubscription.current
        try Task.checkCancellation(); try revalidate()
        if subscription?.canPlayCatalogContent == true {
            var request = MusicCatalogSearchRequest(term: text, types: [Song.self, Album.self, Playlist.self]); request.limit = 5
            let response = try await request.response()
            for song in response.songs { add(.song(song), title: song.title, subtitle: song.artistName, kind: "歌曲") }
            for album in response.albums { add(.album(album), title: album.title, subtitle: album.artistName, kind: "专辑") }
            for playlist in response.playlists { add(.playlist(playlist), title: playlist.name, subtitle: playlist.curatorName ?? "歌单", kind: "歌单") }
            notice = "Apple Music 曲库搜索结果"
        } else {
            var request = MusicLibrarySearchRequest(term: text, types: [Song.self, Album.self, Playlist.self]); request.limit = 5
            let response = try await request.response()
            for song in response.songs { add(.song(song), title: song.title, subtitle: song.artistName, kind: "歌曲") }
            for album in response.albums { add(.album(album), title: album.title, subtitle: album.artistName, kind: "专辑") }
            for playlist in response.playlists { add(.playlist(playlist), title: playlist.name, subtitle: playlist.curatorName ?? "歌单", kind: "歌单") }
            notice = "当前仅查询你的媒体库；可播放范围取决于已购买/同步内容。"
        }
        try Task.checkCancellation(); try revalidate()
        guard marker == generation else { throw CoachPluginError.accountChanged }
        items = cache; choices = found; revision = UUID()
        return found
    }
    func choice(_ token: String) throws -> Choice {
        guard let result = choices.first(where: { $0.id == token }), items[token] != nil else { throw CoachPluginError.stale }
        return result
    }
    /// Replacing the system queue is called only after the user accepts a concrete card.
    func play(_ token: String, revalidate: () throws -> Void) async throws {
        try revalidate()
        guard authorized, let item = items[token] else { throw CoachPluginError.stale }
        let player = SystemMusicPlayer.shared
        switch item {
        case .song(let song): player.queue = .init(for: [song])
        case .album(let album): player.queue = .init(for: album)
        case .playlist(let playlist): player.queue = .init(for: playlist)
        }
        try await player.play()
        try revalidate(); revision = UUID()
    }
    func control(_ action: String, revalidate: () throws -> Void) async throws -> String {
        try revalidate()
        guard authorized else { throw CoachPluginError.unavailable("Apple 音乐尚未授权。") }
        let player = SystemMusicPlayer.shared
        switch action {
        case "pause": player.pause()
        case "resume": try await player.play()
        case "next": try await player.skipToNextEntry()
        case "previous": try await player.skipToPreviousEntry()
        case "status": break
        default: throw CoachPluginError.invalid
        }
        try revalidate(); revision = UUID()
        return "当前曲目：\(currentTitle)；状态：\(playing ? "正在播放" : "未在播放")。"
    }
}
