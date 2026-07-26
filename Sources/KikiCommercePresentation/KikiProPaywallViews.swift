import Combine
import KikiCommerceCore
import KikiPaywall
import SwiftUI

enum KikiAccessPaywallActionKind: Equatable {
    case purchase
    case startTrial
    case restore
    case dismiss

    var stableID: UUID {
        switch self {
        case .purchase:
            return UUID(uuidString: "7B35A7EC-B827-4D8B-A0D2-3AB5C5B8F001")!
        case .startTrial:
            return UUID(uuidString: "7B35A7EC-B827-4D8B-A0D2-3AB5C5B8F002")!
        case .restore:
            return UUID(uuidString: "7B35A7EC-B827-4D8B-A0D2-3AB5C5B8F003")!
        case .dismiss:
            return UUID(uuidString: "7B35A7EC-B827-4D8B-A0D2-3AB5C5B8F004")!
        }
    }
}

enum KikiAccessPaywallOperation: Equatable {
    case purchase
    case restore
    case startTrial
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
            switch context {
            case .onboarding:
                return Self(primary: .startTrial, secondary: [.purchase, .restore])
            case .settings:
                return Self(primary: .purchase, secondary: [.startTrial, .restore])
            }
        }

        return Self(primary: .purchase, secondary: [.restore])
    }
}

/// Whether the paywall offers plans at all.
///
/// An entitled user has already paid. Showing priced plan cards underneath
/// "your access is active" reads as being asked to buy the thing they own,
/// so the sheet drops to a status view: what they have, and a way out.
///
/// This deliberately also hides plans from a subscriber who could in principle
/// move to a higher tier — the kit has no ordering over `CommercePlan`, so it
/// cannot tell an upgrade from a second charge. Cross-tier upgrades need their
/// own framing, not the acquisition paywall.
enum KikiAccessPaywallPlanPolicy {
    static func showsPlans(for status: KikiAccessState) -> Bool {
        !status.isPro
    }
}

@MainActor
final class KikiAccessPaywallWorkflow: ObservableObject {
    @Published private(set) var isLoadingOfferings = false
    @Published private(set) var isStartingTrial = false
    @Published private(set) var lastOperation: KikiAccessPaywallOperation?

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

        lastOperation = .purchase
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

        lastOperation = .restore
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

        lastOperation = .startTrial
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
    private let stats: [KikiAccessPaywallStat]
    private let footerLinks: [KikiAccessPaywallLink]
    private let tint: Color
    private let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String

    public init(
        manager: KikiAccessManager,
        context: KikiAccessPaywallContext,
        copy: KikiAccessPaywallCopy = KikiAccessPaywallCopy(),
        stats: [KikiAccessPaywallStat] = [],
        footerLinks: [KikiAccessPaywallLink] = [],
        tint: Color = .accentColor,
        onFinish: @escaping () -> Void = {}
    ) {
        self.manager = manager
        self.context = context
        self.copy = copy
        self.stats = stats
        self.footerLinks = footerLinks
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
            stats: stats.map {
                KikiPaywallStatConfig(id: $0.id, value: $0.value, label: $0.label)
            },
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

    private var plans: [KikiPaywallPlanPresentation] {
        guard KikiAccessPaywallPlanPolicy.showsPlans(for: manager.status) else {
            return []
        }

        return manager.availablePlans.map { product in
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
                id: kind.stableID,
                title: copy.doneActionTitle,
                action: finish
            )
        }
    }

    private var purchaseAction: KikiPaywallActionPresentation {
        KikiPaywallActionPresentation(
            id: KikiAccessPaywallActionKind.purchase.stableID,
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
            id: KikiAccessPaywallActionKind.startTrial.stableID,
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
            id: KikiAccessPaywallActionKind.restore.stableID,
            title: copy.restoreActionTitle,
            isLoading: manager.isRestoringPurchases,
            style: .footerLink,
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
                    text: operationErrorMessage,
                    tone: .danger
                )
            }
        }
        if workflow.isLoadingOfferings {
            return KikiPaywallMessagePresentation(text: copy.loadingOptionsMessage)
        }
        if manager.availablePlans.allSatisfy({ !$0.isAvailable }),
           manager.status.canStartTrial == false {
            return KikiPaywallMessagePresentation(
                text: copy.unavailableOptionsMessage
            )
        }
        return nil
    }

    private var operationErrorMessage: String {
        switch workflow.lastOperation {
        case .restore:
            return copy.restoreErrorMessage
        case .startTrial:
            return copy.trialErrorMessage
        case .purchase, .none:
            return copy.purchaseErrorMessage
        }
    }

    private func syncSelectedPlan() {
        if manager.planProduct(for: selectedPlanID).isAvailable {
            return
        }

        if let firstAvailablePlan = manager.availablePlans.first(where: \.isAvailable) {
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
