import SwiftUI
import UIKit

struct AccountSettingsView: View {
    @ObservedObject private var auth = AuthStore.shared
    @State private var confirmsLogout = false
    var body: some View {
        Form {
            Group {
            Section {
                LabeledContent("用户名", value: auth.user?.username ?? "")
                NavigationLink("我的邀请码") { InvitationsView() }
                LabeledContent("AI 服务", value: "云端服务")
            }
            Section {
                Text("每个邀请码限注册一个账号。新账号注册后获得 3 个邀请码，受邀者按同样规则继续邀请。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("退出登录", role: .destructive) { confirmsLogout = true }
            } footer: { Text("退出后需重新登录，本机记录保留。") }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
        .navigationTitle("账号与设置")
        .confirmationDialog("退出当前账号？", isPresented: $confirmsLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await auth.logout() } }
            Button("取消", role: .cancel) { }
        }
    }
}

struct InvitationsView: View {
    @State private var invites: [ServiceInvite] = []
    @State private var loading = false
    @State private var error: String?
    @State private var copied: String?
    var body: some View {
        List {
            Group {
            Section {
                Text("把这份陪伴，分享给朋友。") .font(.title2.bold())
                Text("每个邀请码可供一位朋友注册。朋友注册后，也会获得 3 个邀请码。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("正在读取…") }
            if let error {
                Section { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
            }
            ForEach(invites) { invite in
                Section {
                    if let code = invite.code { Text(code).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    HStack {
                        Text(invite.available ? "可使用" : invite.status == "used" ? "已使用" : "已撤销")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if invite.available, let code = invite.code {
                            Button(copied == invite.id ? "已复制" : "复制") {
                                UIPasteboard.general.string = code; copied = invite.id
                            }
                        }
                    }
                }
            }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
        .navigationTitle("我的邀请码")
        .task { await load() }
        .refreshable { await load() }
    }
    @MainActor private func load() async {
        guard !loading, let token = ServiceCredentials.session?.token else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            struct Result: Decodable { let invites: [ServiceInvite] }
            let data = try await AuthAPI.request("/invites", token: token)
            invites = try JSONDecoder().decode(Result.self, from: data).invites
        } catch { self.error = error.localizedDescription }
    }
}
