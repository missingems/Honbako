#if SUMI
import StoreKit
import SwiftUI

/// Compare benefits first, then choose one plan and continue once.
struct HonbakoSubscriptionPlansView: View {
    var continueFree: (() -> Void)?
    var feature: HonbakoProFeature?
    var selection: Binding<HonbakoSubscriptionPlan>?
    @ObservedObject private var store = HonbakoProStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: HonbakoSubscriptionPlan = .annual
    @State private var choseFree = true
    @State private var processingAction = false

    private var planBinding: Binding<HonbakoSubscriptionPlan> { selection ?? $selected }
    private var selectedPlan: HonbakoSubscriptionPlan { planBinding.wrappedValue }
    private var isFreeSelected: Bool { continueFree != nil && choseFree }
    private var selectedProduct: Product? { selectedPlan == .monthly ? store.product : store.annualProduct }
    private var saving: Int? {
        guard let monthly = store.product, let annual = store.annualProduct,
              monthly.priceFormatStyle.currencyCode == annual.priceFormatStyle.currencyCode else { return nil }
        return HonbakoSubscriptionPricing.saving(monthly: monthly.price, annual: annual.price)
    }

    private var memberContinueAction: (() -> Void)? {
        guard continueFree != nil else { return nil }
        return { finishOnboarding() }
    }

    var body: some View {
        Group {
            if store.hasPro {
                HonbakoSubscriptionManagementView(continueReading: memberContinueAction)
            } else if !store.hasCheckedEntitlement {
                ProgressView("Checking subscription…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { HonbakoPaperBackground().ignoresSafeArea() }
            } else {
                contentWithContinueBar
            }
        }
            .task(id: store.hasPro) {
                await store.refreshEntitlement()
                guard !store.hasPro else { return }
                await store.loadProduct()
                if store.annualProduct == nil, store.product != nil { planBinding.wrappedValue = .monthly }
            }
    }

    @ViewBuilder
    private var contentWithContinueBar: some View {
        if #available(iOS 26.0, *) {
            plansForm.safeAreaBar(edge: .bottom, spacing: 0) {
                continueAction.background { HonbakoPaperBackground().ignoresSafeArea(.container, edges: .bottom) }
            }
        } else {
            plansForm.safeAreaInset(edge: .bottom, spacing: 0) { continueAction.background { HonbakoPaperBackground().ignoresSafeArea(.container, edges: .bottom) } }
        }
    }

    private var plansForm: some View {
        Form {
            Group {
                if let feature {
                    Section { Text("\(feature.title) is included with Honbako Pro.") }
                }
                Section("Compare Plans") {
                    HonbakoPlanComparisonView()
                }

                Section {
                    planChoices
                } header: { Text("Choose Plan") } footer: {
                    Button("Restore Purchases") {
                        processingAction = true
                        Task {
                            defer { processingAction = false }
                            await store.restore()
                            if store.hasVerifiedPro { finishOnboarding() }
                        }
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .disabled(store.isLoading || processingAction)
                    .accessibilityIdentifier("Honbako.Plan.Restore")
                }

                if !isFreeSelected {
                    Section {
                        if let product = selectedProduct {
                            if let trial = store.introductoryTrials[product.id] {
                                Text(trial.title).font(.headline)
                                Text(renewalDescription(product: product, plan: selectedPlan))
                                    .accessibilityIdentifier("Honbako.Plan.TrialRenewal")
                            } else {
                                LabeledContent("Billed Amount", value: "\(product.displayPrice) / \(selectedPlan == .monthly ? "month" : "year")")
                            }
                            Text("Auto-renews until canceled in App Store subscriptions.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if store.isLoading {
                            ProgressView("Checking the App Store…")
                        } else {
                            Text("This plan isn’t available from the App Store yet.").foregroundStyle(.secondary)
                            Button("Try Again") { Task { await store.loadProduct() } }
                        }
                    }
                }

                if let message = store.message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                Section {
                    HStack {
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Spacer()
                        Link("Privacy Policy", destination: URL(string: "https://missingems.github.io/Honbako/privacy/")!)
                    }
                    .font(.footnote)
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
    }

    @ViewBuilder
    private var planChoices: some View {
        if continueFree != nil {
            Button { choseFree = true } label: {
                HStack {
                    Text("Free").foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    selectionMark(isFreeSelected)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading || processingAction)
            .accessibilityIdentifier("Honbako.Plan.free")
            .accessibilityValue(isFreeSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isFreeSelected ? .isSelected : [])
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        plan(.monthly, product: store.product)
        plan(.annual, product: store.annualProduct)
    }

    private var continueAction: some View {
        VStack(spacing: 6) {
            if !isFreeSelected, !store.hasPro, let product = selectedProduct {
                Text(renewalDescription(product: product, plan: selectedPlan))
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("Honbako.Plan.RenewalPrice")
            }
            continueButton
        }
        .frame(maxWidth: 440)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var continueButton: some View {
        Button {
            if isFreeSelected || store.hasPro {
                finishOnboarding()
            } else {
                processingAction = true
                Task {
                    defer { processingAction = false }
                    await store.purchase(plan: selectedPlan)
                    if store.hasVerifiedPro { finishOnboarding() }
                }
            }
        } label: {
            HStack {
                if processingAction || (store.isLoading && !isFreeSelected) { ProgressView().tint(.white) }
                Text("Continue").font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(HonbakoPalette.action)
        .foregroundStyle(HonbakoPalette.onAction)
        .controlSize(.large)
        .disabled(processingAction || (!isFreeSelected && store.isLoading) || (!isFreeSelected && !store.hasPro && selectedProduct == nil))
        .accessibilityIdentifier("Honbako.Plan.Continue")
    }

    private func finishOnboarding() {
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: HonbakoWelcomeGate.completionKey)
        defaults.set(HonbakoWelcomeGate.completionVersion(from: previous, arguments: ProcessInfo.processInfo.arguments),
                     forKey: HonbakoWelcomeGate.completionKey)
        if AppSettings.general.icloudSync.get() {
            CloudSyncStatus.shared.start()
            Task { await CloudSyncStatus.shared.refreshAccount() }
        }
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
        if let continueFree { continueFree() }
        else { dismiss() }
    }

    private func selectionMark(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(isSelected ? HonbakoPalette.accent : Color.secondary)
            .accessibilityHidden(true)
    }

    private func renewalDescription(product: Product, plan: HonbakoSubscriptionPlan) -> String {
        let price = product.displayPrice
        if let trial = store.introductoryTrials[product.id] {
            return plan == .monthly
                ? String(localized: "\(trial.durationDescription) free, then \(price) per month · Auto-renews")
                : String(localized: "\(trial.durationDescription) free, then \(price) per year · Auto-renews")
        }
        return plan == .monthly
            ? String(localized: "\(price) per month · Auto-renews")
            : String(localized: "\(price) per year · Auto-renews")
    }

    private func plan(_ plan: HonbakoSubscriptionPlan, product: Product?) -> some View {
        let isSelected = !isFreeSelected && selectedPlan == plan
        return Button {
            choseFree = false
            planBinding.wrappedValue = plan
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan == .monthly ? "Pro per month" : "Pro per year")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let product {
                        if let trial = store.introductoryTrials[product.id] {
                            Text(trial.title)
                                .font(.subheadline.bold()).foregroundStyle(HonbakoPalette.accent)
                                .accessibilityIdentifier("Honbako.Plan.\(plan.rawValue).Trial")
                            Text(plan == .monthly ? "Then \(product.displayPrice) per month" : "Then \(product.displayPrice) per year")
                                .font(.subheadline.bold()).foregroundStyle(.primary)
                        } else {
                            Text(plan == .monthly ? "\(product.displayPrice) per month" : "\(product.displayPrice) per year")
                                .font(.subheadline.bold()).foregroundStyle(.primary)
                        }
                    } else {
                        Text("Price unavailable").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if plan == .annual, let saving {
                        Text("Save \(saving)%").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                selectionMark(isSelected)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading || processingAction)
        .accessibilityIdentifier("Honbako.Plan.\(plan.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
#endif
