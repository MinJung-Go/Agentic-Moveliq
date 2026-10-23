import SwiftUI

struct MiloSettingsView: View {
    @AppStorage(MiloPersona.styleKey) private var style = MiloPersona.Style.sister
    @AppStorage(MiloPersona.nameKey) private var name = "Milo"
    @AppStorage(MiloPersona.preferenceKey) private var preference = ""
    @FocusState private var editing: Bool

    var body: some View {
        Form {
            Group {
            Section("怎么称呼我") {
                TextField("Milo", text: $name).focused($editing)
                    .onChange(of: name) { _, value in name = String(value.prefix(30)) }
            }
            Section("相处方式") {
                ForEach(MiloPersona.Style.allCases) { option in
                    Button { style = option } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.preview).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if style == option { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }.padding(.vertical, 5)
                    }
                    .accessibilityAddTraits(style == option ? .isSelected : [])
                }
            }
            Section {
                TextField("例如：回答简短一点，少用表情", text: $preference, axis: .vertical)
                    .lineLimit(3...5).focused($editing)
                    .onChange(of: preference) { _, value in preference = String(value.prefix(300)) }
            } header: { Text("我希望你……") } footer: {
                Text("可不填写。切换从下一次回复开始生效，历史对话、目标和记录都会保留。")
            }

            }.listRowBackground(Theme.card)
        }.themedListSurface()
        .navigationTitle("Milo · 相处方式")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { editing = false } }
        }
    }
}
