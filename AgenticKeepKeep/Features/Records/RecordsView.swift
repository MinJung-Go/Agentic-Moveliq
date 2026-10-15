import SwiftUI
import SwiftData

/// 记录：按日分组的逆序时间流。
///
/// 视觉上不再是 `List(.insetGrouped)` 的默认外观，而是与今日页同一套卡片语法。
/// 仍然用 `List` 承载是为了保住**原生的左滑删除**与分组头吸顶 —— 那两样自己实现
/// 既费力又不如系统做得顺。做法是让 List 只当骨架：背景、分隔线、行内边距全部接管。
struct RecordsView: View {

    @Environment(\.modelContext) private var context

    /// 默认只加载最近 90 天，避免数据量增长后卡顿
    @Query private var workouts: [WorkoutSession]
    @Query private var meals: [MealEntry]
    @Query private var metrics: [BodyMetric]
    @Query private var notes: [RawNote]
    @Query private var healthWorkouts: [HealthWorkout]

    @State private var searchText = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable {
        case all, workout, meal, other

        var displayName: String {
            switch self {
            case .all: return "全部"
            case .workout: return "训练"
            case .meal: return "饮食"
            case .other: return "其他"
            }
        }
    }

    init() {
        let since = Calendar.current.startOfDay(for: .now).addingTimeInterval(-90 * 86_400)

        _workouts = Query(
            filter: #Predicate<WorkoutSession> { $0.date >= since },
            sort: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        _meals = Query(
            filter: #Predicate<MealEntry> { $0.date >= since },
            sort: [SortDescriptor(\MealEntry.date, order: .reverse)]
        )
        _metrics = Query(
            filter: #Predicate<BodyMetric> { $0.date >= since },
            sort: [SortDescriptor(\BodyMetric.date, order: .reverse)]
        )
        _notes = Query(
            filter: #Predicate<RawNote> { $0.date >= since },
            sort: [SortDescriptor(\RawNote.date, order: .reverse)]
        )
        _healthWorkouts = Query(
            filter: #Predicate<HealthWorkout> { $0.date >= since },
            sort: [SortDescriptor(\HealthWorkout.date, order: .reverse)]
        )
    }

    private var allItems: [RecordItem] {
        RecordItemBuilder.build(
            workouts: workouts,
            meals: meals,
            metrics: metrics,
            notes: notes,
            healthWorkouts: healthWorkouts
        )
    }

    private var filteredItems: [RecordItem] {
        switch filter {
        case .all:
            return allItems
        case .workout:
            return allItems.filter {
                if case .workout = $0.payload { return true }
                if case .healthWorkout = $0.payload { return true }
                return false
            }
        case .meal:
            return allItems.filter { if case .meal = $0.payload { return true }; return false }
        case .other:
            return allItems.filter {
                switch $0.payload {
                case .metric, .rawNote: return true
                default: return false
                }
            }
        }
    }

    private var groups: [RecordGroup] {
        RecordItemBuilder.groupedByDay(filteredItems.filter { item in
            searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText)
                || (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        })
    }

    private var pendingCount: Int {
        allItems.filter(\.isPendingNote).count
    }

    private func delete(_ item: RecordItem) {
        // HealthKit 同步的运动记录只读，源数据在「健康」App
        switch item.payload {
        case .workout(let model): context.delete(model)
        case .meal(let model): context.delete(model)
        case .metric(let model): context.delete(model)
        case .rawNote(let model): context.delete(model)
        case .healthWorkout: return
        }
        try? context.save()
        Haptics.warning()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if pendingCount > 0 && filter == .all {
                    pendingBanner
                }

                if allItems.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        tint: Theme.secondaryLabel,
                        title: "还没有记录",
                        message: "到「今天」页说一句话，或用底部输入条开始记录"
                    )
                    .padding(.horizontal, Theme.Spacing.l)
                    Spacer(minLength: 0)
                } else if groups.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "没有匹配的记录",
                        message: "试试其他关键词或切换记录类型"
                    )
                    .padding(.horizontal, Theme.Spacing.l)
                    Spacer(minLength: 0)
                } else {
                    recordList
                }
            }
            .background(Theme.canvas)
            .navigationTitle("记录")
            .searchable(text: $searchText, prompt: "搜索动作、食物或备注")
        }
    }

    // MARK: - 筛选

    /// 滑动胶囊：选中态用 matchedGeometryEffect 在选项间平移，而不是各自淡入淡出
    private var filterBar: some View {
        FilterSegments(selection: $filter)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - 待归类聚合（FR15.7：放页面顶部，不埋在列表里）

    private var pendingBanner: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.warning)
            Text("有 \(pendingCount) 条笔记待归类")
                .font(Theme.Font.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - 卡片流

    private var recordList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index, count: group.items.count)
                    }
                } header: {
                    sectionHeader(group)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func row(_ item: RecordItem, index: Int, count: Int) -> some View {
        NavigationLink {
            RecordDetailView(item: item)
        } label: {
            cardBody(index: index, count: count) {
                RecordRow(item: item)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.l, bottom: 0, trailing: Theme.Spacing.l))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            if item.isEditable {
                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    /// 一组记录拼成一张卡：首行圆上角、末行圆下角，中间平接。
    /// 这样既保住了 List 的原生交互，又得到卡片的外观。
    private func cardBody<Content: View>(
        index: Int,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFirst = index == 0
        let isLast = index == count - 1

        return VStack(spacing: 0) {
            content()
            if !isLast { RowDivider() }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: isFirst ? Theme.Radius.card : 0,
                bottomLeadingRadius: isLast ? Theme.Radius.card : 0,
                bottomTrailingRadius: isLast ? Theme.Radius.card : 0,
                topTrailingRadius: isFirst ? Theme.Radius.card : 0,
                style: .continuous
            )
            .fill(Theme.card)
        )
    }

    private func sectionHeader(_ group: RecordGroup) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(Format.relativeDay(group.day))
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            Spacer(minLength: 0)
            Text("\(group.items.count) 条")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.tertiaryLabel)
                .monospacedDigit()
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: Theme.Spacing.l, leading: Theme.Spacing.xl, bottom: Theme.Spacing.xs, trailing: Theme.Spacing.xl))
    }
}

/// 分段筛选：选中态的胶囊在选项之间平移
struct FilterSegments: View {

    @Binding var selection: RecordsView.Filter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(RecordsView.Filter.allCases, id: \.self) { value in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(value.displayName)
                        .font(Theme.Font.footnote.weight(.semibold))
                        .foregroundStyle(selection == value ? .primary : Theme.secondaryLabel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 3)
                        .background {
                            if selection == value {
                                Capsule()
                                    .fill(Theme.card)
                                    .matchedGeometryEffect(id: "filterPill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Theme.chip, in: Capsule())
    }
}

#Preview {
    RecordsView()
        .environmentObject(AppState())
        .modelContainer(try! AppModelContainer.inMemory())
}
