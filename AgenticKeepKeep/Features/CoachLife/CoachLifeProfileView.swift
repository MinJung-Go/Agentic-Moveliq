import SwiftData
import SwiftUI

@MainActor
struct CoachLifeProfileView: View {
    @Environment(\.modelContext) private var context
    @State private var profile = CoachLifeProfile()
    @State private var loaded = false
    @State private var message: String?
    @State private var token: String?
    private let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    var body: some View {
        Form {
            Section {
                Text("先告诉 Milo 最重要的几件事。未提供的内容保持未知，临时变化可以另设有效期。")
                    .font(.subheadline).foregroundStyle(Theme.secondaryLabel)
            }
            Section("训练目标") {
                TextField("你希望达到什么目标？", text: $profile.goal, axis: .vertical)
                Picker("训练经验", selection: $profile.experience) {
                    ForEach(["未提供", "刚开始", "有一些基础", "规律训练"], id: \.self) { Text($0).tag($0) }
                }
                Stepper("每周理想 \(profile.weeklySessions) 次", value: $profile.weeklySessions, in: 1...7)
                Stepper("单次约 \(profile.sessionMinutes) 分钟", value: $profile.sessionMinutes, in: 10...180, step: 5)
                TextField("场地与可用器械", text: $profile.equipment, axis: .vertical)
                TextField("常用训练地点（可不填）", text: $profile.location)
            }
            Section {
                ForEach(1...7, id: \.self) { weekday in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(names[weekday - 1], isOn: Binding(get: { profile.windows.contains { $0.weekday == weekday } }, set: { enabled in
                            profile.windows.removeAll { $0.weekday == weekday }
                            if enabled { profile.windows.append(CoachDailyWindow(weekday: weekday, startMinute: 19 * 60, endMinute: 21 * 60)) }
                        }))
                        if let index = profile.windows.firstIndex(where: { $0.weekday == weekday }) {
                            HStack {
                                timePicker("开始", weekday: weekday, minute: profile.windows[index].startMinute, isStart: true)
                                timePicker("结束", weekday: weekday, minute: profile.windows[index].endMinute, isStart: false)
                            }
                        }
                    }
                }
                Stepper("每侧预留 \(profile.bufferMinutes) 分钟", value: $profile.bufferMinutes, in: 0...120, step: 5)
            } header: { Text("允许安排训练的时段") } footer: {
                Text("打开某天后请核对起止时间。预留时间用于准备、通勤或洗漱；还会扣除已选日历中的忙碌时间。")
            }
            Section("其他必须考虑的日常限制") {
                TextField("例如：饭后半小时不训练；周末需要照顾家人", text: $profile.constraints, axis: .vertical).lineLimit(3...6)
            }
            Section("不可占用的时间") {
                ForEach($profile.protectedTimes) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("例如：晚饭、照顾家人", text: $item.label)
                        Picker("星期", selection: $item.weekday) { ForEach(1...7, id: \.self) { Text(names[$0 - 1]).tag($0) } }
                        protectedPicker("开始", minute: $item.startMinute)
                        protectedPicker("结束", minute: $item.endMinute)
                    }
                }.onDelete { profile.protectedTimes.remove(atOffsets: $0) }
                Button("添加保护时段") { profile.protectedTimes.append(.init(weekday: 2, startMinute: 18 * 60, endMinute: 19 * 60, label: "")) }
                    .disabled(profile.protectedTimes.count >= 30)
            }
            Section {
                NavigationLink("自动调整范围") { CoachAutomationSettingsView() }
                NavigationLink("连接日历与其他插件") { CoachPluginsView() }
                Button("清除这些偏好", role: .destructive) { profile = CoachLifeProfile(); save() }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("我的训练与日常").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { profile.confirmed = true; save() }.disabled(!loaded) } }
        .task {
            do { profile = try CoachLifeStore.profile(context); token = ServiceCredentials.session?.token; loaded = true }
            catch { message = error.localizedDescription }
        }
    }
    private func timePicker(_ title: String, weekday: Int, minute: Int, isStart: Bool) -> some View {
        DatePicker(title, selection: Binding(get: {
            CoachLifeTime.at(minute: minute, on: .now) ?? .now
        }, set: { date in
            guard let index = profile.windows.firstIndex(where: { $0.weekday == weekday }) else { return }
            let value = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            if isStart { profile.windows[index].startMinute = value } else { profile.windows[index].endMinute = value }
        }), displayedComponents: .hourAndMinute)
    }
    private func save() {
        do { try CoachLifeStore.checkAccount(context: context, token: token); try CoachLifeStore.save(profile: profile, in: context); message = "已保存，下次规划会重新核对。" }
        catch { message = "未能保存：\(error.localizedDescription)" }
    }
    private func protectedPicker(_ title: String, minute: Binding<Int>) -> some View {
        DatePicker(title, selection: Binding(get: { CoachLifeTime.at(minute: minute.wrappedValue, on: .now) ?? .now }, set: {
            minute.wrappedValue = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
        }), displayedComponents: .hourAndMinute)
    }
}

@MainActor
struct CoachTemporaryStateView: View {
    var checkIn: CoachCheckIn? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var expires = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var error: String?
    @State private var token: String?
    var body: some View {
        Form {
            Section("告诉 Milo 今天有什么变化") {
                TextField("例如：临时加班、出差、只有20分钟、今天很疲惫", text: $note, axis: .vertical).lineLimit(3...6)
                DatePicker("有效至", selection: $expires, in: Date()...Date().addingTimeInterval(30 * 86400))
            }
            Section {
                Text("只在有效期内用于规划，不永久当作你的生活习惯。保存后可回到今日安排，让 Milo 重新评估。")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
                Button("保存这次变化") {
                    do {
                        try CoachLifeStore.checkAccount(context: context, token: token)
                        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.count <= 500, expires > .now else { throw CoachPluginError.invalid }
                        try context.save()
                        let value = checkIn ?? CoachCheckIn(kind: "temporary")
                        if checkIn == nil { context.insert(value) }
                        value.note = note; value.expiresAt = expires
                        value.availableMinutes = CoachLifeTime.statedMinutes(note)
                        do { try context.save() } catch { context.rollback(); throw error }
                        NotificationCenter.default.post(name: .coachLifeChanged, object: nil); dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                if let checkIn {
                    Button("移除这次变化", role: .destructive) {
                        do {
                            try CoachLifeStore.checkAccount(context: context, token: token); try context.save()
                            context.delete(checkIn)
                            do { try context.save() } catch { context.rollback(); throw error }
                            NotificationCenter.default.post(name: .coachLifeChanged, object: nil); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(Theme.danger) }
        }.navigationTitle("今天有变化").task {
            token = ServiceCredentials.session?.token
            if let checkIn { note = checkIn.note; expires = checkIn.expiresAt }
        }
    }
}
