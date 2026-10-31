#if SUMI
import SwiftUI

struct HonbakoWelcomeView: View {
    let onFinish: () -> Void
    @State private var navigation: HonbakoWelcomeNavigation
    @State private var subscriptionPlan = HonbakoSubscriptionPlan.annual

    init(onFinish: @escaping () -> Void, startingAt page: HonbakoWelcomePage = .library) {
        self.onFinish = onFinish
        _navigation = State(initialValue: HonbakoWelcomeNavigation(startingAt: page))
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            HonbakoWelcomeIntroList(page: .library)
                .safeAreaInset(edge: .bottom, spacing: 0) { nextAction(for: .library) }
                .navigationDestination(for: HonbakoWelcomePage.self) { page in
                    switch page {
                    case .library, .assistant:
                        HonbakoWelcomeIntroList(page: page)
                            .safeAreaInset(edge: .bottom, spacing: 0) { nextAction(for: page) }
                    case .plans:
                        HonbakoSubscriptionPlansView(continueFree: onFinish, selection: $subscriptionPlan)
                            .navigationTitle("Plans")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .tint(HonbakoPalette.accent)
    }

    @ViewBuilder
    private func nextAction(for page: HonbakoWelcomePage) -> some View {
        if page.next != nil {
            Button(action: navigation.advance) {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HonbakoPalette.action)
            .foregroundStyle(HonbakoPalette.onAction)
            .controlSize(.large)
            .accessibilityIdentifier("Honbako.Welcome.Next")
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background { HonbakoPaperBackground().ignoresSafeArea(.container, edges: .bottom) }
        }
    }
}
#endif
