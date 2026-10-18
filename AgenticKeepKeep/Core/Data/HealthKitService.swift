import Foundation
import HealthKit
import SwiftData

/// HealthKit 只读桥接：把睡眠 / HRV / 静息心率 / 步数 / 运动记录同步进本地库。
/// 约定：只读，不回写 HealthKit。
@MainActor
final class HealthKitService: ObservableObject {

    static let shared = HealthKitService()

    static let authorizationRequestedKey = "healthkit.authorizationRequested"
    static let lastSyncKey = "healthkit.lastSync"
    static let stateKey = "healthkit.authorizationState"

    /// 授权状态（决定界面上给什么引导）
    enum AuthorizationState: String {
        /// 还没问过用户
        case notRequested
        /// 设备不支持健康数据
        case unavailable
        /// 上次授权检测到签名缺少 HealthKit 权限；重新签名后允许重试
        case unsupportedSigning
        /// 授权请求失败（其他原因）
        case failed
        /// 已请求授权（HealthKit 不告知读权限是否被拒，只能靠能否读到数据判断）
        case requested

        var title: String {
            switch self {
            case .notRequested: return "未接入"
            case .unavailable: return "设备不支持"
            case .unsupportedSigning: return "上次授权缺少权限"
            case .failed: return "授权失败"
            case .requested: return "已请求授权（只读）"
            }
        }
    }

    private let store = HKHealthStore()
    private let healthDataAvailable: () -> Bool
    private let defaults: UserDefaults
    private let authorizationRequest: ((Set<HKObjectType>) async throws -> Void)?

    @Published private(set) var isAuthorizing = false

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var hasRequestedAuthorization: Bool
    @Published private(set) var authorizationState: AuthorizationState

    init(defaults: UserDefaults = .standard,
         authorizationRequest: ((Set<HKObjectType>) async throws -> Void)? = nil,
         healthDataAvailable: @escaping () -> Bool = { HKHealthStore.isHealthDataAvailable() }) {
        self.healthDataAvailable = healthDataAvailable
        self.authorizationRequest = authorizationRequest
        self.defaults = defaults
        self.hasRequestedAuthorization = defaults.bool(forKey: Self.authorizationRequestedKey)
        self.lastSyncDate = defaults.object(forKey: Self.lastSyncKey) as? Date
        self.authorizationState = defaults.string(forKey: Self.stateKey)
            .flatMap(AuthorizationState.init(rawValue:)) ?? .notRequested
    }

    var isAvailable: Bool { healthDataAvailable() }

    /// 上次授权的错误状态不代表重新安装后的签名状态，始终允许重试。
    var isSigningUnsupported: Bool { authorizationState == .unsupportedSigning }

    static let signingHelp = "上次授权时，系统报告缺少 HealthKit 签名权限。请使用能启用 HealthKit 的签名方式覆盖安装后，点击重新授权。不能仅凭此错误判断是否需要付费账号，其他记录与分析功能不受影响。"

    var authorizationActionTitle: String {
        if isAuthorizing { return "授权中…" }
        if isSyncing { return "同步中…" }
        if authorizationState == .unsupportedSigning || authorizationState == .failed {
            return "重新授权并同步"
        }
        return hasRequestedAuthorization ? "重新同步健康数据" : "授权并同步健康数据"
    }

    /// 给人看的说明文案
    var statusMessage: String? {
        switch authorizationState {
        case .notRequested:
            return nil
        case .unavailable:
            return "此设备不支持健康数据。"
        case .unsupportedSigning:
            return Self.signingHelp
        case .failed:
            return lastError
        case .requested:
            return nil
        }
    }

    /// HealthKit 的底层错误码：缺 entitlement（HKErrorMissingEntitlement）
    private static let healthKitErrorDomain = "com.apple.healthkit"
    private static let missingEntitlementCode = 4

    /// 读取的数据类型
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        types.insert(HKObjectType.workoutType())
        for identifier in Self.quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    private static let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN,
        .restingHeartRate,
        .stepCount,
        .activeEnergyBurned
    ]

    // MARK: - 授权

    /// 请求读取授权。HealthKit 出于隐私不告知「读」是否被拒绝，只能用是否读到数据来判断。
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard !isAuthorizing, !isSyncing else { return false }
        isAuthorizing = true
        defer { isAuthorizing = false }
        guard isAvailable else {
            update(state: .unavailable, error: "此设备不支持健康数据。")
            return false
        }

        do {
            if let authorizationRequest {
                try await authorizationRequest(readTypes)
            } else {
                try await store.requestAuthorization(toShare: [], read: readTypes)
            }
            hasRequestedAuthorization = true
            defaults.set(true, forKey: Self.authorizationRequestedKey)
            update(state: .requested, error: nil)
            return true
        } catch {
            let (state, message) = Self.classify(error)
            update(state: state, error: message)
            return false
        }
    }

    /// 把 HealthKit 的底层错误翻译成用户能理解、能处理的说明
    static func classify(_ error: Error) -> (AuthorizationState, String) {
        let nsError = error as NSError

        if nsError.domain == healthKitErrorDomain {
            if nsError.code == missingEntitlementCode {
                return (
                    .unsupportedSigning,
                    Self.signingHelp
                )
            }
            if nsError.code == 1 {
                return (.unavailable, "此设备不支持健康数据。")
            }
        }

        // 兜底：不同系统版本的错误描述里同样会提到 entitlement
        if error.localizedDescription.lowercased().contains("entitlement") {
            return (
                .unsupportedSigning,
                Self.signingHelp
            )
        }

        return (.failed, "授权失败：\(error.localizedDescription)")
    }

    private func update(state: AuthorizationState, error: String?) {
        authorizationState = state
        lastError = error
        defaults.set(state.rawValue, forKey: Self.stateKey)
    }

    /// 授权失败时停止，不让同步覆盖原始错误。
    @discardableResult
    func authorizeAndSync(into context: ModelContext) async -> Bool {
        let marker = accountGeneration
        guard await requestAuthorization(), marker == accountGeneration else { return false }
        do {
            var config = try CoachLifeStore.plugins(context)
            config.healthEnabled = true
            try CoachLifeStore.save(plugins: config, in: context)
        } catch { lastError = "健康连接设置未保存：\(error.localizedDescription)"; return false }
        await sync(days: 30, into: context)
        return marker == accountGeneration && lastError == nil
    }

    private var accountGeneration = UUID()
    func reloadAccountMetadata() {
        accountGeneration = UUID()
        lastSyncDate = defaults.object(forKey: Self.lastSyncKey) as? Date
        lastError = nil
    }

    // MARK: - 同步

    /// 同步最近若干天的数据（幂等：同一天/同一运动重复同步只更新）
    func sync(days: Int = 30, into context: ModelContext) async {
        guard isAvailable else {
            update(state: .unavailable, error: "此设备不支持健康数据。")
            return
        }
        guard !isSyncing, !isAuthorizing, authorizationState == .requested else { return }
        do {
            guard try CoachLifeStore.plugins(context).healthEnabled != false else { return }
        } catch { lastError = "无法读取健康连接设置：\(error.localizedDescription)"; return }

        let accountMarker = accountGeneration
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let calendar = Calendar.current
        let end = Date()
        let startDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: end) ?? end)

        do {
            let sleep = try await sleepHoursByDay(start: startDay, end: end)
            let hrv = try await dailyStatistics(
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                options: .discreteAverage,
                start: startDay,
                end: end
            )
            let restingHeartRate = try await dailyStatistics(
                identifier: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                options: .discreteAverage,
                start: startDay,
                end: end
            )
            let steps = try await dailyStatistics(
                identifier: .stepCount,
                unit: .count(),
                options: .cumulativeSum,
                start: startDay,
                end: end
            )
            let energy = try await dailyStatistics(
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                options: .cumulativeSum,
                start: startDay,
                end: end
            )

            let workouts = try await fetchWorkouts(start: startDay, end: end)
            guard accountMarker == accountGeneration,
                  try CoachLifeStore.plugins(context).healthEnabled != false else { return }

            try upsertSnapshots(
                days: days,
                startDay: startDay,
                sleep: sleep,
                hrv: hrv,
                restingHeartRate: restingHeartRate,
                steps: steps,
                energy: energy,
                context: context
            )

            try upsertWorkouts(workouts, context: context)

            try context.save()

            guard accountMarker == accountGeneration else { return }
            lastSyncDate = .now
            defaults.set(lastSyncDate, forKey: Self.lastSyncKey)
        } catch {
            guard accountMarker == accountGeneration else { return }
            lastError = "同步失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 查询辅助

    /// 今日快照
    func todaySnapshot(in context: ModelContext) -> HealthSnapshot? {
        let day = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<HealthSnapshot>(predicate: #Predicate { $0.day == day })
        return try? context.fetch(descriptor).first
    }

    // MARK: - 健康数据读取

    private func dailyStatistics(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let anchor = Calendar.current.startOfDay(for: start)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var values: [Date: Double] = [:]
                let calendar = Calendar.current
                results?.enumerateStatistics(from: anchor, to: end) { statistics, _ in
                    let day = calendar.startOfDay(for: statistics.startDate)
                    if options.contains(.cumulativeSum), let sum = statistics.sumQuantity() {
                        values[day] = sum.doubleValue(for: unit)
                    } else if options.contains(.discreteAverage), let average = statistics.averageQuantity() {
                        values[day] = average.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: values)
            }

            store.execute(query)
        }
    }

    private func sleepHoursByDay(start: Date, end: Date) async throws -> [Date: Double] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        var totals: [Date: Double] = [:]

        for sample in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            // 只统计真正睡着的时段（不含「在床上」「清醒」）
            switch value {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                break
            default:
                continue
            }
            // 跨夜睡眠归到「起床那天」
            let day = calendar.startOfDay(for: sample.endDate)
            totals[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }

        return totals
    }

    private func fetchWorkouts(start: Date, end: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - 落库（幂等 upsert）

    private func upsertSnapshots(
        days: Int,
        startDay: Date,
        sleep: [Date: Double],
        hrv: [Date: Double],
        restingHeartRate: [Date: Double],
        steps: [Date: Double],
        energy: [Date: Double],
        context: ModelContext
    ) throws {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: .now)

        // 一次性取出区间内已有快照，避免逐日查询
        let descriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.day >= startDay },
            sortBy: [SortDescriptor(\.day)]
        )
        let existing = try context.fetch(descriptor)
        var byDay: [Date: HealthSnapshot] = [:]
        for snapshot in existing {
            byDay[calendar.startOfDay(for: snapshot.day)] = snapshot
        }

        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let normalized = calendar.startOfDay(for: day)
            if normalized > endDay { break }

            let sleepHours = sleep[normalized] ?? 0
            let hrvValue = hrv[normalized] ?? 0
            let heartRate = restingHeartRate[normalized] ?? 0
            let stepCount = Int((steps[normalized] ?? 0).rounded())
            let energyValue = energy[normalized] ?? 0

            // 完全没有数据的日期不建空记录
            if sleepHours == 0 && hrvValue == 0 && heartRate == 0 && stepCount == 0 && energyValue == 0 {
                continue
            }

            if let snapshot = byDay[normalized] {
                snapshot.sleepHours = sleepHours
                snapshot.hrvMs = hrvValue
                snapshot.restingHeartRate = heartRate
                snapshot.steps = stepCount
                snapshot.activeEnergyKcal = energyValue
                snapshot.updatedAt = .now
            } else {
                context.insert(HealthSnapshot(
                    day: normalized,
                    sleepHours: sleepHours,
                    hrvMs: hrvValue,
                    restingHeartRate: heartRate,
                    steps: stepCount,
                    activeEnergyKcal: energyValue
                ))
            }
        }
    }

    private func upsertWorkouts(_ workouts: [HKWorkout], context: ModelContext) throws {
        guard !workouts.isEmpty else { return }

        let existing = try context.fetch(FetchDescriptor<HealthWorkout>())
        let known = Set(existing.map(\.healthKitUUID))

        for workout in workouts {
            let uuid = workout.uuid.uuidString
            guard !known.contains(uuid) else { continue }

            let distanceMeters: Double? = workout.totalDistance?.doubleValue(for: .meter())

            var averageHeartRate: Double?
            if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
               let statistics = workout.statistics(for: heartRateType),
               let average = statistics.averageQuantity() {
                let unit = HKUnit.count().unitDivided(by: .minute())
                averageHeartRate = average.doubleValue(for: unit)
            }

            context.insert(HealthWorkout(
                healthKitUUID: uuid,
                date: workout.startDate,
                activityName: Self.activityName(for: workout.workoutActivityType),
                durationMinutes: workout.duration / 60,
                distanceKm: distanceMeters.map { $0 / 1_000 },
                averageHeartRate: averageHeartRate,
                sourceName: workout.sourceRevision.source.name
            ))
        }
    }

    // MARK: - 运动类型名称

    static func activityName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .traditionalStrengthTraining: return "力量训练"
        case .functionalStrengthTraining: return "功能性力量"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "瑜伽"
        case .pilates: return "普拉提"
        case .coreTraining: return "核心训练"
        case .hiking: return "徒步"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .stairClimbing: return "爬楼"
        case .jumpRope: return "跳绳"
        case .dance: return "舞蹈"
        case .basketball: return "篮球"
        case .soccer: return "足球"
        case .badminton: return "羽毛球"
        case .tableTennis: return "乒乓球"
        case .tennis: return "网球"
        case .skatingSports: return "滑冰"
        case .mindAndBody: return "身心训练"
        case .cooldown: return "放松"
        case .flexibility: return "拉伸"
        default: return "运动"
        }
    }
}
