import SwiftUI

/// First authenticated launch: selected services, serial system prompts, or skip.
/// RootView retains the existing account-scoped completion key, so upgrades do not re-prompt.
struct OnboardingView: View {
    var onFinish: () -> Void
    var body: some View {
        NavigationStack {
            ServiceConnectionView(onFinish: onFinish)
        }
        .task { await NetworkAccessBootstrap.shared.requestOnce() }
    }
}
