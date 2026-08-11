import Combine
import KikiCommerceCore
import KikiPaywall
import SwiftUI

enum KikiAccessPaywallActionKind: Equatable {
    case purchase
    case startTrial
    case restore
    case dismiss
}

struct KikiAccessPaywallActionPolicy: Equatable {
    let primary: KikiAccessPaywallActionKind
    let secondary: [KikiAccessPaywallActionKind]

    static func resolve(
        status: KikiAccessState,
        context: KikiAccessPaywallContext
    ) -> Self {
        if status.isPro {
            return Self(primary: .dismiss, secondary: [])
        }

        if status.canStartTrial {
            return Self(primary: .purchase, secondary: [.startTrial, .restore])
        }

        return Self(primary: .purchase, secondary: [.restore])
    }
}

@MainActor
final class KikiAccessPaywallWorkflow: ObservableObject {
    @Published private(set) var isLoadingOfferings = false
    @Published private(set) var isStartingTrial = false

    private let manager: KikiAccessManager

    init(manager: KikiAccessManager) {
        self.manager = manager
    }

    var isBusy: Bool {
        isLoadingOfferings
            || isStartingTrial
            || manager.purchaseInProgressPlanID != nil
            || manager.isRestoringPurchases
    }

    func loadOfferings() async {
        guard !isBusy else {
            return
        }

        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        await manager.loadOfferings()
    }

    func purchase(planID: String) async -> Bool {
        guard !isBusy else {
            return false
        }

        do {
            try await manager.purchase(planID: planID)
            return manager.status.isPro
        } catch {
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard !isBusy else {
            return false
        }

        do {
            try await manager.restorePurchases()
            return manager.status.isPro
        } catch {
            return false
        }
    }

    func startTrial() async -> Bool {
        guard !isBusy else {
            return false
        }

        isStartingTrial = true
        defer { isStartingTrial = false }
        await manager.startTrial()
        return manager.status.isActive
    }
}

public struct KikiAccessPaywallSheet: View {
    @ObservedObject private var manager: KikiAccessManager
    @StateObject private var workflow: KikiAccessPaywallWorkflow
    private let context: KikiAccessPaywallContext
    private let copy: KikiAccessPaywallCopy
    private let footerLinks: [KikiAccessPaywallLink]
    private let displayPlanIDs: [String]?
    private let tint: Color
    private let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String

    /// - Parameter displayPlanIDs: plans this sheet shows, in order. `nil`
    ///   shows every configured plan. Pass a subset when the configuration
    ///   carries plans that are sold elsewhere — a win-back discount SKU must
    ///   be purchasable through the manager without appearing as a third card
    ///   on the regular paywall, where it would undercut the listed price.
    public init(
        manager: KikiAccessManager,
        context: KikiAccessPaywallContext,
        copy: KikiAccessPaywallCopy = KikiAccessPaywallCopy(),
        footerLinks: [KikiAccessPaywallLink] = [],
        displayPlanIDs: [String]? = nil,
        tint: Color = .accentColor,
        onFinish: @escaping () -> Void = {}
    ) {
        self.manager = manager
        self.context = context
        self.copy = copy
        self.footerLinks = footerLinks
        self.displayPlanIDs = displayPlanIDs
        self.tint = tint
        self.onFinish = onFinish
        _workflow = StateObject(wrappedValue: KikiAccessPaywallWorkflow(manager: manager))
        _selectedPlanID = State(initialValue: manager.configuration.defaultPlanID)
    }

    public var body: some View {
        let presentation = makePresentation()
        return Group {
            switch context {
            case .onboarding:
                KikiOnboardingPaywall(presentation: presentation, selectedPlanID: $selectedPlanID, tint: tint)
            case .settings:
                KikiCompactPaywall(
                    presentation: presentation,
                    selectedPlanID: $selectedPlanID,
                    tint: tint,
                    showsCloseButton: true
                )
            }
        }
        .task {
            await workflow.loadOfferings()
            syncSelectedPlan()
        }
        .onChange(of: manager.availablePlans) { _ in
            syncSelectedPlan()
        }
        .interactiveDismissDisabled(context == .onboarding)
    }

    private func makePresentation() -> KikiPaywallPresentation {
        KikiPaywallPresentation(
            accessState: accessState,
            headerTitle: copy.title,
            headerSubtitle: subtitle,
            plans: plans,
            features: copy.features,
            footnote: nil,
            footerLinks: footerLinks.map {
                KikiPaywallLinkPresentation(id: $0.id, title: $0.title, url: $0.url)
            },
            message: message,
            isInteractionDisabled: workflow.isBusy,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
            dismiss: finish
        )
    }

    private var accessState: KikiPaywallAccessState {
        switch manager.status {
        case .notStarted:
            return .notStarted
        case .trial:
            return .trial
        case .expired:
            return .expired
        case .pro(let plan, _):
            return .entitled(planTitle: plan.title)
        }
    }

    private var subtitle: String {
        switch manager.status {
        case .notStarted:
            return copy.notStartedSubtitle
        case .trial:
            return copy.trialSubtitle
        case .expired:
            return copy.expiredSubtitle
        case .pro:
            return copy.proSubtitle
        }
    }

    private var displayedPlans: [KikiAccessPlanProduct] {
        Self.displayedPlans(from: manager.availablePlans, displayPlanIDs: displayPlanIDs)
    }

    static func displayedPlans(
        from availablePlans: [KikiAccessPlanProduct],
        displayPlanIDs: [String]?
    ) -> [KikiAccessPlanProduct] {
        guard let displayPlanIDs else {
            return availablePlans
        }
        return displayPlanIDs.compactMap { id in
            availablePlans.first { $0.id == id }
        }
    }

    private var plans: [KikiPaywallPlanPresentation] {
        displayedPlans.map { product in
            KikiPaywallPlanPresentation(
                id: product.id,
                title: product.title,
                displayPrice: product.displayPrice,
                billingDetail: product.billingDetail,
                badge: product.badge,
                isAvailable: product.isAvailable
            )
        }
    }

    private var primaryAction: KikiPaywallActionPresentation {
        actionPresentation(for: actionPolicy.primary)
    }

    private var secondaryActions: [KikiPaywallActionPresentation] {
        actionPolicy.secondary.map(actionPresentation(for:))
    }

    private var actionPolicy: KikiAccessPaywallActionPolicy {
        .resolve(status: manager.status, context: context)
    }

    private func actionPresentation(
        for kind: KikiAccessPaywallActionKind
    ) -> KikiPaywallActionPresentation {
        switch kind {
        case .purchase:
            return purchaseAction
        case .startTrial:
            return trialAction
        case .restore:
            return restoreAction
        case .dismiss:
            return KikiPaywallActionPresentation(
                title: copy.doneActionTitle,
                action: finish
            )
        }
    }

    private var purchaseAction: KikiPaywallActionPresentation {
        KikiPaywallActionPresentation(
            title: copy.purchaseActionTitle,
            isLoading: manager.purchaseInProgressPlanID != nil,
            isEnabled: { planID in
                manager.planProduct(for: planID).isAvailable
            },
            action: { planID in
                run {
                    await workflow.purchase(planID: planID)
                }
            }
        )
    }

    private var trialAction: KikiPaywallActionPresentation {
        KikiPaywallActionPresentation(
            title: copy.trialActionTitle,
            isLoading: workflow.isStartingTrial,
            action: {
                run {
                    await workflow.startTrial()
                }
            }
        )
    }

    private var restoreAction: KikiPaywallActionPresentation {
        KikiPaywallActionPresentation(
            title: copy.restoreActionTitle,
            isLoading: manager.isRestoringPurchases,
            action: {
                run {
                    await workflow.restorePurchases()
                }
            }
        )
    }

    private func run(_ operation: @escaping @MainActor () async -> Bool) {
        Task<Void, Never> {
            if await operation() {
                finish()
            }
        }
    }

    private var message: KikiPaywallMessagePresentation? {
        if let feedback = manager.commerceFeedback {
            switch feedback {
            case .purchaseSucceeded:
                return KikiPaywallMessagePresentation(
                    text: copy.purchaseSuccessMessage,
                    tone: .success
                )
            case .restoreSucceeded:
                return KikiPaywallMessagePresentation(
                    text: copy.restoreSuccessMessage,
                    tone: .success
                )
            case .noActivePurchase:
                return KikiPaywallMessagePresentation(
                    text: copy.noActivePurchaseMessage,
                    tone: .warning
                )
            case .error:
                return KikiPaywallMessagePresentation(
                    text: copy.purchaseErrorMessage,
                    tone: .danger
                )
            }
        }
        if workflow.isLoadingOfferings {
            return KikiPaywallMessagePresentation(text: copy.loadingOptionsMessage)
        }
        if displayedPlans.allSatisfy({ !$0.isAvailable }),
           manager.status.canStartTrial == false {
            return KikiPaywallMessagePresentation(
                text: copy.unavailableOptionsMessage
            )
        }
        return nil
    }

    private func syncSelectedPlan() {
        let displayed = displayedPlans
        if displayed.contains(where: { $0.id == selectedPlanID && $0.isAvailable }) {
            return
        }

        if let firstAvailablePlan = displayed.first(where: \.isAvailable) {
            selectedPlanID = firstAvailablePlan.id
        }
    }

    private func finish() {
        if context == .settings {
            dismiss()
        }
        onFinish()
    }
}
