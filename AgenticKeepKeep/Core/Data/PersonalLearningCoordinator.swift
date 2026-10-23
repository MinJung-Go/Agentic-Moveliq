import Foundation
import SwiftData

/// Durable, bounded, foreground-only learning. No OS background execution promise.
@MainActor final class PersonalLearningCoordinator {
    static let shared = PersonalLearningCoordinator()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var foreground = false
    private var conversationsInFlight = 0
    private weak var attachedContext: ModelContext?

    func setForeground(_ value: Bool, context: ModelContext) {
        if !value {
            guard attachedContext?.container === context.container else { return }
            foreground = false; cancelCurrent(); return
        }
        guard AppModelContainer.active === context.container, ServiceCredentials.session != nil else { return }
        if attachedContext?.container !== context.container { cancelCurrent(); conversationsInFlight = 0 }
        attachedContext = context; foreground = true
        do { _ = try PersonalKnowledgeStore.load(context) } catch { return }
        resume(context)
    }
    func beginChat() { conversationsInFlight += 1; cancelCurrent() }
    func endChat(context: ModelContext) {
        guard attachedContext?.container === context.container else { return }
        conversationsInFlight = max(0, conversationsInFlight - 1); resume(context)
    }
    func cancelCurrent() { generation = UUID(); task?.cancel(); task = nil }

    func enqueue(conversation: UUID, context: ModelContext, historical: Bool = false) throws {
        let token = ServiceCredentials.session?.token
        let state = try PersonalKnowledgeStore.load(context)
        var sources = try PersonalKnowledgeStore.sources(context, conversation: conversation)
        if !historical { sources = sources.filter { $0.date >= state.enabledAt } }
        guard !sources.isEmpty else { return }
        // Manual history walks bounded windows, automatic learning only the latest task slice.
        if !historical { sources = Array(sources.suffix(6)) }
        var windows: [[KnowledgeSource]] = [], current: [KnowledgeSource] = [], bytes = 0
        for source in sources {
            if bytes + source.text.utf8.count > 9000 || current.count == 6 {
                if !current.isEmpty { windows.append(current) }; current = []; bytes = 0
            }
            current.append(source); bytes += source.text.utf8.count
        }
        if !current.isEmpty { windows.append(current) }
        try PersonalKnowledgeStore.mutate(context, token: token) { state in
            for window in windows {
                let ids = window.map(\.id), receipts = window.filter(\.operationCompleted).map(\.id)
                guard !state.jobs.contains(where: { $0.sourceIDs == ids && $0.completedReceiptIDs == receipts && $0.state != "cancelled" }) else { continue }
                if !historical {
                    let covered = Set(ids)
                    for i in state.jobs.indices where state.jobs[i].conversationID == conversation && !state.jobs[i].historical
                        && ["queued", "running"].contains(state.jobs[i].state) && Set(state.jobs[i].sourceIDs).isSubset(of: covered) {
                        state.jobs[i].state = "cancelled"; state.jobs[i].error = "已合并到后续对话的整理任务。"
                    }
                }
                state.jobs.append(.init(conversationID: conversation, sourceIDs: ids, historical: historical, completedReceiptIDs: receipts))
            }
        }
        resume(context)
    }
    func retry(job: UUID, context: ModelContext) throws {
        try PersonalKnowledgeStore.mutate(context, token: ServiceCredentials.session?.token) { state in
            guard let i = state.jobs.firstIndex(where: { $0.id == job }), state.jobs[i].state == "failed" else { return }
            state.jobs[i].state = "queued"; state.jobs[i].attempts = 0; state.jobs[i].error = nil
        }
        resume(context)
    }
    func cancel(job: UUID, context: ModelContext) throws {
        try CoachLifeStore.checkAccount(context: context, token: ServiceCredentials.session?.token)
        if try PersonalKnowledgeStore.load(context).jobs.contains(where: { $0.id == job && $0.state == "running" }) { cancelCurrent() }
        try PersonalKnowledgeStore.mutate(context, token: ServiceCredentials.session?.token) { state in
            if let i = state.jobs.firstIndex(where: { $0.id == job }) { state.jobs[i].state = "cancelled" }
        }
        resume(context)
    }
    func resume(_ context: ModelContext) {
        guard foreground, conversationsInFlight == 0, task == nil, AppModelContainer.active === context.container else { return }
        let run = UUID(); generation = run
        let token = ServiceCredentials.session?.token
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == run { self.task = nil } }
            // Let UI / current reply finish first; persisted queued jobs survive suspension.
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            while !Task.isCancelled, self.generation == run {
                var running: KnowledgeJob?
                do {
                    try CoachLifeStore.checkAccount(context: context, token: token)
                    let state = try PersonalKnowledgeStore.load(context)
                    guard let job = state.jobs.first(where: { $0.state == "queued" || $0.state == "running" }) else { return }
                    running = job
                    let sources = try PersonalKnowledgeStore.sources(context, conversation: job.conversationID, ids: job.sourceIDs)
                    guard sources.count == job.sourceIDs.count else { throw KnowledgeError.invalid("原会话内容已删除，本次整理已停止。") }
                    try self.update(job.id, context: context, token: token) { $0.state = "running"; $0.attempts += 1; $0.error = nil }
                    let agent = try PersonalKnowledgeStore.learningAgent(client: LLMSettings.shared.makeRecordingClient())
                    let profile = try CoachLifeStore.profile(context).summary
                    let proposals = try await agent.extract(sources: sources, existing: PersonalKnowledgeStore.related(state, sources: sources), profile: profile)
                    for (index, proposal) in proposals.enumerated() {
                        try Task.checkCancellation()
                        guard self.generation == run else { return }
                        let latest = try PersonalKnowledgeStore.load(context)
                        guard latest.jobs.contains(where: { $0.id == job.id && $0.state == "running" }) else { throw CancellationError() }
                        let item = latest.items.first { $0.id == proposal.skillID }
                        let evidence = try await agent.verify(proposal: proposal, sources: sources, current: item)
                        try Task.checkCancellation()
                        guard self.generation == run else { return }
                        guard try PersonalKnowledgeStore.load(context).jobs.contains(where: { $0.id == job.id && $0.state == "running" }) else { throw CancellationError() }
                        guard try PersonalKnowledgeStore.sources(context, conversation: job.conversationID, ids: job.sourceIDs) == sources else { throw KnowledgeError.conflict }
                        try PersonalKnowledgeStore.apply(proposal, evidence: evidence, operationID: "learning:\(job.id):\(index)", context: context, token: token)
                    }
                    try self.update(job.id, context: context, token: token) { $0.state = "completed"; $0.error = nil }
                } catch {
                    guard self.generation == run, !Task.isCancelled else { return }
                    if let job = running {
                        // No unbounded paid retries. Explicit Retry remains available in the history screen.
                        try? self.update(job.id, context: context, token: token) { $0.state = "failed"; $0.error = String(error.localizedDescription.prefix(240)) }
                    } else { return }
                }
            }
        }
    }
    private func update(_ id: UUID, context: ModelContext, token: String?, change: (inout KnowledgeJob) -> Void) throws {
        try PersonalKnowledgeStore.mutate(context, token: token) { state in
            guard let i = state.jobs.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
            guard state.jobs[i].state != "cancelled" else { throw CancellationError() }
            change(&state.jobs[i])
        }
    }
}
