import Foundation
import SwiftUI

public struct KikiProPlan: Equatable, Identifiable, Sendable {
    public let id: String
    public let commercePlan: CommercePlan
    public let title: String
    public let fallbackDisplayPrice: String
    public let billingDetail: String
    public let subtitle: String
    public let badge: String?

    public init(
        id: String,
        commercePlan: CommercePlan,
        title: String,
        fallbackDisplayPrice: String,
        billingDetail: String,
        subtitle: String,
        badge: String? = nil
    ) {
        self.id = id
        self.commercePlan = commercePlan
        self.title = title
        self.fallbackDisplayPrice = fallbackDisplayPrice
        self.billingDetail = billingDetail
        self.subtitle = subtitle
        self.badge = badge
    }
}

public struct KikiProPlanProduct: Equatable, Identifiable, Sendable {
    public let plan: KikiProPlan
    public let displayPrice: String
    public let billingDetail: String
    public let isAvailable: Bool

    public var id: String { plan.id }
    public var title: String { plan.title }
    public var subtitle: String { plan.subtitle }
    public var badge: String? { plan.badge }

    public init(
        plan: KikiProPlan,
        displayPrice: String,
        billingDetail: String,
        isAvailable: Bool
    ) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.billingDetail = billingDetail
        self.isAvailable = isAvailable
    }

    public static func fallback(for plan: KikiProPlan, isAvailable: Bool = true) -> Self {
        Self(
            plan: plan,
            displayPrice: plan.fallbackDisplayPrice,
            billingDetail: plan.billingDetail,
            isAvailable: isAvailable
        )
    }
}

public enum KikiProAccessStatus: Equatable {
    case notStarted
    case trial(daysRemaining: Int, expiresAt: Date)
    case expired
    case pro(plan: KikiProPlan, entitlement: CommerceEntitlement)

    public var isActive: Bool {
        switch self {
        case .trial, .pro:
            return true
        case .notStarted, .expired:
            return false
        }
    }

    public var isPro: Bool {
        if case .pro = self {
            return true
        }
        return false
    }

    public var canStartTrial: Bool {
        if case .notStarted = self {
            return true
        }
        return false
    }

    public var displayName: String {
        switch self {
        case .notStarted:
            return "Trial not started"
        case .trial(let daysRemaining, _):
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left"
        case .expired:
            return "Trial ended"
        case .pro:
            return "Pro"
        }
    }

    public var renewalState: KikiProRenewalState? {
        renewalState(now: Date())
    }

    public func renewalState(now: Date) -> KikiProRenewalState? {
        guard case .pro(let plan, let entitlement) = self,
              entitlement.expirationDate != nil else {
            return nil
        }

        let expirationDate = entitlement.expirationDate!
        let remaining = expirationDate.timeIntervalSince(now)
        let daysRemaining = remaining > 0 ? max(1, Int(ceil(remaining / 86_400))) : 0

        if entitlement.willRenew {
            return .renews(on: expirationDate, daysRemaining: daysRemaining, plan: plan)
        }

        return .ends(on: expirationDate, daysRemaining: daysRemaining, plan: plan)
    }
}

public enum KikiProRenewalState: Equatable {
    case renews(on: Date, daysRemaining: Int, plan: KikiProPlan)
    case ends(on: Date, daysRemaining: Int, plan: KikiProPlan)
}

public enum KikiTrialPolicy: Equatable, Sendable {
    case explicitStart(duration: TimeInterval)
    case autoStart(duration: TimeInterval)
    case disabled

    public static let defaultExplicit = KikiTrialPolicy.explicitStart(duration: 2 * 24 * 60 * 60)

    public var duration: TimeInterval? {
        switch self {
        case .explicitStart(let duration), .autoStart(let duration):
            return duration
        case .disabled:
            return nil
        }
    }
}

public struct KikiProAccessStorageKeys: Equatable, Sendable {
    public let trialStartedAt: String
    public let debugProAccessOverride: String

    public init(
        trialStartedAt: String,
        debugProAccessOverride: String
    ) {
        self.trialStartedAt = trialStartedAt
        self.debugProAccessOverride = debugProAccessOverride
    }

    public static func prefixed(_ prefix: String) -> Self {
        Self(
            trialStartedAt: "\(prefix).trialStartedAt",
            debugProAccessOverride: "\(prefix).debugProAccessOverride"
        )
    }
}

public struct KikiProAccessMessages: Equatable, Sendable {
    public let purchaseSuccess: String
    public let restoreSuccess: String
    public let noActivePurchase: String

    public init(
        purchaseSuccess: String = "Purchase successful. Pro unlocked.",
        restoreSuccess: String = "Purchase restored.",
        noActivePurchase: String = "No active purchase found on this account."
    ) {
        self.purchaseSuccess = purchaseSuccess
        self.restoreSuccess = restoreSuccess
        self.noActivePurchase = noActivePurchase
    }
}

public struct KikiProAccessConfiguration: Sendable {
    public let plans: [KikiProPlan]
    public let defaultPlanID: String
    public let commerceConfiguration: CommerceConfiguration
    public let trialPolicy: KikiTrialPolicy
    public let storageKeys: KikiProAccessStorageKeys
    public let messages: KikiProAccessMessages

    public init(
        plans: [KikiProPlan],
        defaultPlanID: String,
        commerceConfiguration: CommerceConfiguration,
        trialPolicy: KikiTrialPolicy = .defaultExplicit,
        storageKeys: KikiProAccessStorageKeys,
        messages: KikiProAccessMessages = KikiProAccessMessages()
    ) {
        self.plans = plans
        self.defaultPlanID = defaultPlanID
        self.commerceConfiguration = commerceConfiguration
        self.trialPolicy = trialPolicy
        self.storageKeys = storageKeys
        self.messages = messages
    }
}

public struct KikiProExternalLinks: Equatable, Sendable {
    public let termsURL: String?
    public let privacyURL: String?
    public let supportURL: String?

    public init(
        termsURL: String? = nil,
        privacyURL: String? = nil,
        supportURL: String? = nil
    ) {
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.supportURL = supportURL
    }
}

public struct KikiProPaywallCopy: Equatable, Sendable {
    public let title: String
    public let proSubtitle: String
    public let trialSubtitle: String
    public let expiredSubtitle: String
    public let notStartedSubtitle: String
    public let proCardTitle: String
    public let proCardSubtitle: String
    public let features: [String]

    public init(
        title: String = "Choose your plan",
        proSubtitle: String = "All features are unlocked.",
        trialSubtitle: String = "Choose a plan or continue with your trial.",
        expiredSubtitle: String = "Your trial has ended. Upgrade to keep using Pro.",
        notStartedSubtitle: String = "Choose a plan or start your free trial.",
        proCardTitle: String = "Pro",
        proCardSubtitle: String = "All features unlocked - thank you for your support.",
        features: [String] = []
    ) {
        self.title = title
        self.proSubtitle = proSubtitle
        self.trialSubtitle = trialSubtitle
        self.expiredSubtitle = expiredSubtitle
        self.notStartedSubtitle = notStartedSubtitle
        self.proCardTitle = proCardTitle
        self.proCardSubtitle = proCardSubtitle
        self.features = features
    }
}

public enum KikiProPaywallPresentationContext: Equatable, Sendable {
    case settings
    case onboarding
}

public struct KikiProPaywallLayout: Equatable, Sendable {
    public let settingsSize: CGSize
    public let onboardingSize: CGSize
    public let settingsPadding: CGFloat
    public let onboardingPadding: CGFloat

    public init(
        settingsSize: CGSize = CGSize(width: 500, height: 520),
        onboardingSize: CGSize = CGSize(width: 560, height: 620),
        settingsPadding: CGFloat = 28,
        onboardingPadding: CGFloat = 34
    ) {
        self.settingsSize = settingsSize
        self.onboardingSize = onboardingSize
        self.settingsPadding = settingsPadding
        self.onboardingPadding = onboardingPadding
    }

    public static let commandReopenDefault = KikiProPaywallLayout()

    public func size(for context: KikiProPaywallPresentationContext) -> CGSize {
        context == .onboarding ? onboardingSize : settingsSize
    }

    public func padding(for context: KikiProPaywallPresentationContext) -> CGFloat {
        context == .onboarding ? onboardingPadding : settingsPadding
    }
}
