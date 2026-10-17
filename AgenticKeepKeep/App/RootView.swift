import SwiftData
import SwiftUI

/// 底部 5 Tab：今日 / 记录 / 课程表 / 洞察 / 设置
struct RootView: View {

    @AppStorage private var hasCompletedOnboarding: Bool

    init(accountKey: String = "preview") {
        _hasCompletedOnboarding = AppStorage(wrappedValue: false, "onboarding." + accountKey)
    }
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var health = HealthKitService.shared

    @Query private var tutorialPlans: [Plan]
    @Query(sort: [SortDescriptor(\ChatMessage.date)]) private var tutorialMessages: [ChatMessage]
    @ObservedObject private var llmSettings = LLMSettings.shared
    private var tutorialNames: [String] {
        let saved = tutorialPlans.filter { $0.isActive }.flatMap { $0.days.flatMap { $0.exercises.map(\.name) } }
        let pending = tutorialMessages.last { $0.hasPendingPlan }
        let draft = pending?.pendingPlanJSON.flatMap { try? JSONDecoder().decode(PlanDraft.self, from: Data($0.utf8)) }
        return Array(Set(saved + (draft?.days.flatMap { $0.exercises.map(\.name) } ?? []))).sorted()
    }
    private var tutorialTaskID: String { tutorialNames.joined(separator: "|") + "|\(llmSettings.useLocalModel)|\(llmSettings.webSearchEnabled)|\(llmSettings.supportsWebSearch)|\(llmSettings.isConfigured)" }

    @AppStorage(MiloPersona.nameKey) private var miloName = "Milo"

    @StateObject private var appState = AppState()
    @StateObject private var logging = LoggingViewModel()
    @ObservedObject private var siri = SiriEntryRouter.shared

    /// 记录弹窗默认全高（对话流需要空间），仍可下拉到半屏
    @State private var quickLogDetent: PresentationDetent = .large

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainTabs
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $appState.selectedTab) {
            // Tab 用实心变体（Apple 设置页那种），轮廓留给与文字并排的位置
            TodayView()
                .tag(AppState.Tab.today)
                .tabItem { Label(MiloPersona(name: miloName).name, systemImage: "bubble.left.fill") }

            RecordsView()
                .tag(AppState.Tab.records)
                .tabItem { Label("记录", systemImage: "list.bullet") }

            PlanView()
                .tag(AppState.Tab.plan)
                .tabItem { Label("课程表", systemImage: "calendar") }

            InsightsView()
                .tag(AppState.Tab.insights)
                .tabItem { Label("洞察", systemImage: "chart.bar.fill") }

            SettingsView()
                .tag(AppState.Tab.settings)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .task(id: tutorialTaskID) {
            if llmSettings.useLocalModel || !llmSettings.webSearchEnabled || !llmSettings.supportsWebSearch || !llmSettings.isConfigured { ExerciseTutorialStore.shared.stopAll() }
            await ExerciseTutorialStore.shared.enrich(names: tutorialNames, context: context)
        }
        .tint(Theme.accent)
        // 导航层通栏实底（FR13.1）：内容从下方滚过时不该透出来
        .toolbarBackground(appState.selectedTab == .today ? Theme.conversationCanvas : Theme.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(appState)
        .onReceive(siri.$pending) { entry in handleSiri(entry) }
        .task { handleSiri(siri.pending) }
        .task { CoachAutomationCoordinator.shared.setForeground(scenePhase == .active, context: context) }
        .onReceive(NotificationCenter.default.publisher(for: .coachLifeChanged)) { _ in
            if scenePhase == .active { CoachAutomationCoordinator.shared.schedule(context: context) }
        }
        .onReceive(health.$lastSyncDate) { _ in
            if scenePhase == .active { CoachAutomationCoordinator.shared.schedule(context: context) }
        }
        .onChange(of: scenePhase) { _, value in
            CoachAutomationCoordinator.shared.setForeground(value == .active, context: context)
        }
        .onDisappear { CoachAutomationCoordinator.shared.setForeground(false, context: context) }
        .sheet(isPresented: $appState.showsCoachDay) { NavigationStack { CoachDashboardView() }.environmentObject(appState) }
        .sheet(isPresented: $appState.showsMiloChat) { CoachChatView().environmentObject(appState) }
        .sheet(isPresented: $appState.isQuickLogPresented, onDismiss: {
            quickLogDetent = .large
        }) {
            QuickLogSheet(viewModel: logging)
                .environmentObject(appState)
                .presentationDetents([.medium, .large], selection: $quickLogDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.card)
        }
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                ToastView(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toast)
        .task {
            // 半途而废的训练草稿超过 24 小时就清掉 ——
            // 不然它们会在库里堆着，下次进来还被问「继续吗」
            WorkoutSessionViewModel.purgeStaleDrafts(in: context)
        }
    }

    private func handleSiri(_ entry: SiriEntryRouter.Entry?) {
        guard let entry, let session = ServiceCredentials.session,
              entry.accountID == AppModelContainer.accountKey(userID: session.user.id, server: ServiceEndpoint.baseURL),
              AppModelContainer.active === context.container else { return }
        siri.pending = nil
        switch entry.route {
        case "today": appState.selectedTab = .today; appState.showsCoachDay = true
        case "chat": appState.selectedTab = .today; appState.showsMiloChat = true
        case "record":
            appState.pendingLogText = entry.text; appState.pendingLogPhoto = nil; appState.isQuickLogPresented = true
        default: break
        }
    }
}

/// 顶部短暂提示
struct ToastView: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.chip, lineWidth: 0.5))
            .shadow(radius: 8, y: 4)
            .padding(.top, 6)
    }
}

#Preview {
    RootView()
        .modelContainer(try! AppModelContainer.inMemory())
}
