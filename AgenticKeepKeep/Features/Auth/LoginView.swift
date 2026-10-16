import SwiftUI

struct LoginView: View {
    @ObservedObject private var auth = AuthStore.shared
    @State private var registration = false
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var invite = ""
    @State private var consent = false
    @State private var visible = false
    @State private var validation: String?
    @State private var showHelp = false
    @State private var showPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { BrandMark(size: 36); Text("Moveliq").font(.title3.bold()) }
                    .padding(.bottom, 20)
                Text(registration ? "从一份邀请开始。" : "欢迎回来。")
                    .font(.largeTitle.bold())
                Text("和 Milo 一起，继续记录你的日常。")
                    .foregroundStyle(.secondary)
                if registration {
                    field("邀请码") {
                        TextField("例如 K7MP-9X4R（旧码也可用）", text: $invite).textContentType(.none)
                    }
                }
                field("用户名") {
                    TextField("4–24 位字母、数字或下划线", text: $username).textContentType(.username)
                }
                field(registration ? "设置密码" : "密码") {
                    HStack {
                        Group {
                            if visible { TextField("至少 12 位", text: $password) }
                            else { SecureField("至少 12 位", text: $password) }
                        }.textContentType(registration ? .newPassword : .password)
                        Button(visible ? "隐藏" : "显示") { visible.toggle() }
                            .buttonStyle(PlainActionButtonStyle(font: .caption))
                    }
                }
                if registration {
                    field("确认密码") {
                        SecureField("再次输入密码", text: $confirmation).textContentType(.newPassword)
                    }
                    Toggle(isOn: $consent) {
                        Button("已阅读并同意服务与隐私说明") { showPrivacy = true }
                            .font(.footnote)
                    }.toggleStyle(.switch)
                }
                if let message = validation ?? auth.message {
                    Text(message).font(.footnote).foregroundStyle(Theme.danger)
                }
                Button {
                    submit()
                } label: {
                    HStack {
                        if auth.busy { ProgressView().tint(Theme.secondaryLabel) }
                        Text(auth.busy ? "请稍候…" : registration ? "创建账号" : "登录")
                    }
                }.buttonStyle(PrimaryButtonStyle()).disabled(auth.busy)
                if !registration {
                    Button("忘记密码？") { showHelp = true }.font(.footnote)
                }
                Button(registration ? "已有账号？返回登录" : "有邀请码？创建账号") {
                    registration.toggle(); validation = nil; auth.message = nil
                    password = ""; confirmation = ""; visible = false
                }.buttonStyle(SecondaryButtonStyle()).disabled(auth.busy)
                Text("登录后可使用云端 AI，无需填写模型密钥。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(24)
        }
        .background(Theme.conversationCanvas)
        .alert("忘记密码", isPresented: $showHelp) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("请联系提供邀请码的管理员，并按要求核验账号归属。不要发送原密码。管理员重置密码后，旧登录会话将失效。")
        }
        .sheet(isPresented: $showPrivacy) { NavigationStack { PrivacyInfoView() } }
        .onDisappear { password = ""; confirmation = ""; visible = false }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            content()
                .font(Theme.Font.body)
                .accessibilityLabel(title)
                .accessibilityHint(validation ?? auth.message ?? "")
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.m)
                .frame(minHeight: 48)
                .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.inner))
        }
    }
    private func submit() {
        validation = nil
        guard AuthInputPolicy.validUsername(username), AuthInputPolicy.validPassword(password) else {
            validation = "用户名需为 4–24 位字母、数字或下划线，密码为 12–128 位。"; return
        }
        if registration {
            guard !AuthInputPolicy.inviteCode(invite).isEmpty else { validation = "请输入邀请码。"; return }
            guard password == confirmation else { validation = "两次输入的密码不一致。"; return }
            guard consent else { validation = "请先阅读并同意服务与隐私说明。"; return }
        }
        Task { await auth.authenticate(username: username, password: password, invite: registration ? invite : nil) }
    }
}
