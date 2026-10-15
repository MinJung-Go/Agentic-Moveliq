import SwiftUI
import SwiftData

/// 按日浏览的记录流，与首页共用时间栏和连续内容栏。
/// List 保留原生滑动删除与分组头吸顶，去掉拼接白卡和额外的行内缩进。
struct RecordsView: View {

    @Environment(\.modelContext) private var context

    /// 默认只加载最近 90 天，避免数据量增长后卡顿
    @Query private var workouts: [WorkoutSession]
    @Query private var meals: [MealEntry]
    @Query private var metrics: [BodyMetric]
    @Query private var notes: [RawNote]
    @Query private var healthWorkouts: [HealthWorkout]

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var filter: Filter = .all
    @State private var selectedRecord: RecordItem?

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
        RecordItemBuilder.groupedByDay(filteredItems.filter { $0.matchesSearch(searchText) })
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
                searchBar
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
                    .padding(.horizontal, Theme.Journal.inset)
                    Spacer(minLength: 0)
                } else if groups.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "没有匹配的记录",
                        message: "试试其他关键词或切换记录类型"
                    )
                    .padding(.horizontal, Theme.Journal.inset)
                    Spacer(minLength: 0)
                } else {
                    recordList
                }
            }
            .background(Theme.Journal.canvas)
            .foregroundStyle(Theme.Journal.label)
            .tint(Theme.Journal.action)
            .toolbarBackground(Theme.Journal.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.Journal.canvas, for: .tabBar)
            .navigationTitle("记录")
            .navigationDestination(isPresented: showsRecordDetail) {
                if let selectedRecord { RecordDetailView(item: selectedRecord) }
            }
        }
    }

    // MARK: - 筛选

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Journal.metadata)
            TextField("搜索动作、食物或备注", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }
                .accessibilityLabel("搜索记录")
                .accessibilityIdentifier("records.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Journal.metadata)
                .accessibilityLabel("清除搜索")
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .padding(.leading, Theme.Spacing.m)
        .padding(.trailing, searchText.isEmpty ? Theme.Spacing.m : 0)
        .background(Theme.Journal.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, Theme.Journal.inset)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var filterBar: some View {
        FilterSegments(selection: $filter)
            .padding(.horizontal, Theme.Journal.inset)
            .padding(.bottom, Theme.Spacing.xl)
    }

    /// 使用可访问的整行按钮，避免 List 的默认 disclosure 额外挤占共享行宽度。
    private var showsRecordDetail: Binding<Bool> {
        Binding(get: { selectedRecord != nil }, set: { if !$0 { selectedRecord = nil } })
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
        .background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
        .padding(.horizontal, Theme.Journal.inset)
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - 记录流

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
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func row(_ item: RecordItem, index: Int, count: Int) -> some View {
        Button {
            isSearchFocused = false
            selectedRecord = item
        } label: {
            VStack(spacing: 0) {
                RecordRow(item: item)
                if index < count - 1 { RecordRowDivider() }
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Journal.inset, bottom: 0, trailing: Theme.Journal.inset))
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

    private func sectionHeader(_ group: RecordGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(Format.relativeDay(group.day))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Journal.label)
            if Calendar.current.isDateInToday(group.day) || Calendar.current.isDateInYesterday(group.day) {
                Text(Format.shortDay(group.day))
                    .font(.caption)
                    .foregroundStyle(Theme.Journal.metadata)
            }
            Spacer(minLength: 0)
            Text("\(group.items.count) 条")
                .font(.caption)
                .foregroundStyle(Theme.Journal.metadata)
                .monospacedDigit()
        }
        .textCase(nil)
        .background(Theme.Journal.canvas)
        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Journal.inset,
                                 bottom: Theme.Spacing.xs, trailing: Theme.Journal.inset))
    }
}

/// 32pt 视觉高度与 44pt 点击范围分开，避免厚胶囊抢占内容空间。
struct FilterSegments: View {

    @Binding var selection: RecordsView.Filter
    @Namespace private var namespace
    @ScaledMetric(relativeTo: .footnote) private var trackHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: 3) {
            ForEach(RecordsView.Filter.allCases, id: \.self) { value in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(value.displayName)
                        .font(Theme.Font.footnote.weight(.semibold))
                        .foregroundStyle(selection == value ? Theme.Journal.label : Theme.Journal.secondary)
                        .frame(maxWidth: .infinity, minHeight: max(44, trackHeight + 12))
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.Journal.canvas)
                                    .frame(height: trackHeight - 4)
                                    .matchedGeometryEffect(id: "filterPill", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.Journal.fill)
                .frame(height: trackHeight)
        }
    }
}

#Preview {
    RecordsView()
        .environmentObject(AppState())
        .modelContainer(try! AppModelContainer.inMemory())
}
