import Foundation

public enum KikiAccessReadiness: Equatable, Sendable {
    case idle
    case loading
    case ready
    case degraded(message: String)

    public var hasResolvedInitialRefresh: Bool {
        switch self {
        case .ready, .degraded:
            return true
        case .idle, .loading:
            return false
        }
    }

    /// Automatic onboarding/paywall decisions should require authoritative
    /// entitlement state. A degraded result may continue cached access but must
    /// not treat a missing entitlement as proof that the user is unpaid.
    public var allowsAutomaticPresentation: Bool {
        self == .ready
    }
}

public struct KikiAccessPlan: Equatable, Identifiable, Sendable {
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

public struct KikiAccessPlanProduct: Equatable, Identifiable, Sendable {
    public let plan: KikiAccessPlan
    public let displayPrice: String
    public let billingDetail: String
    public let isAvailable: Bool

    public var id: String { plan.id }
    public var title: String { plan.title }
    public var subtitle: String { plan.subtitle }
    public var badge: String? { plan.badge }

    public init(
        plan: KikiAccessPlan,
        displayPrice: String,
        billingDetail: String,
        isAvailable: Bool
    ) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.billingDetail = billingDetail
        self.isAvailable = isAvailable
    }

    public static func fallback(for plan: KikiAccessPlan, isAvailable: Bool = true) -> Self {
        Self(
            plan: plan,
            displayPrice: plan.fallbackDisplayPrice,
            billingDetail: plan.billingDetail,
            isAvailable: isAvailable
        )
    }
}

public enum KikiTrialProgress: Equatable, Sendable {
    case time(daysRemaining: Int, expiresAt: Date)
    case usage(eventID: String, used: Int, limit: Int)

    public var remainingUsage: Int? {
        guard case .usage(_, let used, let limit) = self else {
            return nil
        }
        return max(0, limit - used)
    }
}

public enum KikiAccessState: Equatable {
    case notStarted
    case trial(KikiTrialProgress)
    case expired
    case pro(plan: KikiAccessPlan, entitlement: CommerceEntitlement)

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

    public var renewalState: KikiAccessRenewalState? {
        renewalState(now: Date())
    }

    public func renewalState(now: Date) -> KikiAccessRenewalState? {
        guard case .pro(let plan, let entitlement) = self,
              let expirationDate = entitlement.expirationDate else {
            return nil
        }

        let remaining = expirationDate.timeIntervalSince(now)
        let daysRemaining = remaining > 0 ? max(1, Int(ceil(remaining / 86_400))) : 0

        if entitlement.willRenew {
            return .renews(on: expirationDate, daysRemaining: daysRemaining, plan: plan)
        }

        return .ends(on: expirationDate, daysRemaining: daysRemaining, plan: plan)
    }
}

public enum KikiAccessRenewalState: Equatable {
    case renews(on: Date, daysRemaining: Int, plan: KikiAccessPlan)
    case ends(on: Date, daysRemaining: Int, plan: KikiAccessPlan)
}

public enum KikiAccessDebugMode: String, CaseIterable, Sendable {
    case live
    case notPro
    case trial
    /// A trial that ran out. Distinct from `notPro`, which is a trial that
    /// never began: the two differ in what the app may offer next — a win-back
    /// or retention path has a decision to answer only after a trial expired.
    case expired
    case pro

    public var displayName: String {
        switch self {
        case .live: return "Live"
        case .notPro: return "Not Pro"
        case .trial: return "Trial"
        case .expired: return "Expired"
        case .pro: return "Pro"
        }
    }
}

public enum KikiTrialStartTrigger: Equatable, Sendable {
    case explicit
    case automatic
}

public enum KikiTrialPolicy: Equatable, Sendable {
    case time(duration: TimeInterval, startsOn: KikiTrialStartTrigger)
    case usage(eventID: String, limit: Int)
    case disabled

    public static let defaultExplicit = KikiTrialPolicy.time(
        duration: 2 * 24 * 60 * 60,
        startsOn: .explicit
    )

    public static func explicitStart(duration: TimeInterval) -> Self {
        .time(duration: duration, startsOn: .explicit)
    }

    public static func autoStart(duration: TimeInterval) -> Self {
        .time(duration: duration, startsOn: .automatic)
    }
}

@MainActor
public protocol KikiUsageMeter: AnyObject {
    func usage(for eventID: String) -> Int
    func record(eventID: String)
}

@MainActor
public final class KikiUserDefaultsUsageMeter: KikiUsageMeter {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func usage(for eventID: String) -> Int {
        defaults.integer(forKey: key(for: eventID))
    }

    public func record(eventID: String) {
        defaults.set(usage(for: eventID) + 1, forKey: key(for: eventID))
    }

    private func key(for eventID: String) -> String {
        "\(keyPrefix).\(eventID)"
    }
}

@MainActor
public final class KikiInMemoryUsageMeter: KikiUsageMeter {
    private var counts: [String: Int]

    public init(counts: [String: Int] = [:]) {
        self.counts = counts
    }

    public func usage(for eventID: String) -> Int {
        counts[eventID, default: 0]
    }

    public func record(eventID: String) {
        counts[eventID, default: 0] += 1
    }
}

public struct KikiAccessStorageKeys: Equatable, Sendable {
    public let trialStartedAt: String
    public let debugProAccessOverride: String
    public let usageCountPrefix: String

    public init(
        trialStartedAt: String,
        debugProAccessOverride: String,
        usageCountPrefix: String = "KikiCommerce.usage"
    ) {
        self.trialStartedAt = trialStartedAt
        self.debugProAccessOverride = debugProAccessOverride
        self.usageCountPrefix = usageCountPrefix
    }

    public static func prefixed(_ prefix: String) -> Self {
        Self(
            trialStartedAt: "\(prefix).trialStartedAt",
            debugProAccessOverride: "\(prefix).debugProAccessOverride",
            usageCountPrefix: "\(prefix).usage"
        )
    }
}

public enum KikiCommerceFeedback: Equatable, Sendable {
    case purchaseSucceeded
    case restoreSucceeded
    case noActivePurchase
    case error(CommercePurchaseError)
}

public struct KikiAccessConfiguration: Sendable {
    public let plans: [KikiAccessPlan]
    public let defaultPlanID: String
    public let commerceConfiguration: CommerceConfiguration
    public let trialPolicy: KikiTrialPolicy
    public let storageKeys: KikiAccessStorageKeys

    public init(
        plans: [KikiAccessPlan],
        defaultPlanID: String,
        commerceConfiguration: CommerceConfiguration,
        trialPolicy: KikiTrialPolicy = .defaultExplicit,
        storageKeys: KikiAccessStorageKeys
    ) {
        self.plans = plans
        self.defaultPlanID = defaultPlanID
        self.commerceConfiguration = commerceConfiguration
        self.trialPolicy = trialPolicy
        self.storageKeys = storageKeys
    }
}
