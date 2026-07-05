import AppKit
import KikiCommerceCore
import KikiPaywall
import SwiftUI

public struct KikiProPaywallSheet: View {
    @ObservedObject private var manager: KikiProAccessManager
    private let context: KikiProPaywallPresentationContext
    private let copy: KikiProPaywallCopy
    private let tint: Color
    private let onFinish: () -> Void

    @State private var selectedPlanID: String

    public init(
        manager: KikiProAccessManager,
        context: KikiProPaywallPresentationContext,
        copy: KikiProPaywallCopy = KikiProPaywallCopy(),
        tint: Color = .accentColor,
        onFinish: @escaping () -> Void = {}
    ) {
        self.manager = manager
        self.context = context
        self.copy = copy
        self.tint = tint
        self.onFinish = onFinish
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
    }

    private func makePresentation() -> KikiPaywallPresentation {
        KikiPaywallPresentation(
            accessState: accessState,
            headerTitle: copy.title,
            headerSubtitle: subtitle,
            plans: plans,
            features: copy.features,
            footnote: nil,
            isPurchaseInFlight: manager.purchaseInProgressPlanID != nil,
            isRestoreInFlight: manager.isRestoringPurchases,
            actions: actions
        )
    }

    private var accessState: KikiPaywallAccessState {
        switch manager.status {
        case .notStarted:
            return .notStarted
        case .trial(let daysRemaining, _):
            return .trial(daysRemaining: daysRemaining)
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
        manager.availablePlans.map { product in
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

    private var actions: KikiPaywallActions {
        KikiPaywallActions(
            purchase: { planID in
                Task<Void, Never> { try? await manager.purchase(planID: planID) }
            },
            restore: {
                Task<Void, Never> { try? await manager.restorePurchases() }
            },
            startTrial: startTrialAction,
            dismiss: onFinish
        )
    }

    private var startTrialAction: (@MainActor () -> Void)? {
        guard manager.status.canStartTrial else {
            return nil
        }
        return {
            Task<Void, Never> { await manager.startTrial() }
        }
    }
}
