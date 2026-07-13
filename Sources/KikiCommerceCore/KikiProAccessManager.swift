import Combine
import Foundation

@MainActor
public final class KikiAccessManager: ObservableObject {
    public enum Constants {
        public static let transactionRefreshAttempts = 3
        public static let transactionRefreshDelayNanoseconds: UInt64 = 750_000_000
    }

    @Published public private(set) var status: KikiAccessState
    @Published public private(set) var readiness: KikiAccessReadiness
    @Published public private(set) var availablePlans: [KikiAccessPlanProduct]
    @Published public private(set) var lastError: CommercePurchaseError?
    @Published public private(set) var purchaseInProgressPlanID: String?
    @Published public private(set) var isRestoringPurchases = false
    @Published public private(set) var commerceFeedback: KikiCommerceFeedback?
#if DEBUG
    @Published public private(set) var debugProAccessOverride: KikiAccessDebugMode?
#endif

    public var currentEntitlementSnapshot: CommerceEntitlement? {
        entitlementSnapshot
    }

    public let configuration: KikiAccessConfiguration

    private let defaults: UserDefaults
    private let commerceClient: any CommerceClient
    private let usageMeter: any KikiUsageMeter
    private let now: () -> Date

    private var entitlementSnapshot: CommerceEntitlement?
    private var currentOffering: CommerceOffering?
    private var hasConfigured = false
    private var expirationTask: Task<Void, Never>?

    public init(
        configuration: KikiAccessConfiguration,
        defaults: UserDefaults = .standard,
        commerceClient: any CommerceClient,
        usageMeter: (any KikiUsageMeter)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let client = commerceClient
        self.configuration = configuration
        self.defaults = defaults
        self.commerceClient = client
        self.usageMeter = usageMeter ?? KikiUserDefaultsUsageMeter(
            defaults: defaults,
            keyPrefix: configuration.storageKeys.usageCountPrefix
        )
        self.now = now
        self.entitlementSnapshot = client.cachedEntitlement
        self.readiness = .idle
        self.currentOffering = nil
        self.availablePlans = Self.makeAvailablePlans(
            plans: configuration.plans,
            packageMetadata: nil
        )
        self.lastError = nil
        self.purchaseInProgressPlanID = nil
        self.commerceFeedback = nil
#if DEBUG
        self.debugProAccessOverride = Self.readDebugProAccessOverride(
            defaults: defaults,
            keys: configuration.storageKeys
        )
#endif
        Self.startAutoTrialIfNeeded(configuration: configuration, defaults: defaults, now: now)
        self.status = Self.computeStatus(
            configuration: configuration,
            entitlementSnapshot: client.cachedEntitlement,
            defaults: defaults,
            usageMeter: self.usageMeter,
            now: now
        )
        scheduleExpirationIfNeeded()
    }

    deinit {
        expirationTask?.cancel()
    }

    public func configureIfNeeded() {
        guard !hasConfigured else {
            return
        }

        commerceClient.entitlementDidChange = { [weak self] snapshot in
            self?.entitlementSnapshot = snapshot
            self?.readiness = .ready
            self?.applyStatus(self?.computeStatus() ?? .expired)
        }
        commerceClient.configureIfNeeded()
        entitlementSnapshot = commerceClient.cachedEntitlement
        hasConfigured = true
        Self.startAutoTrialIfNeeded(configuration: configuration, defaults: defaults, now: now)
        applyStatus(computeStatus())
    }

    public func refresh() async {
        configureIfNeeded()
        readiness = .loading

        do {
            entitlementSnapshot = try await commerceClient.refreshEntitlement()
            lastError = nil
            readiness = .ready
        } catch {
            let purchaseError = CommercePurchaseError(error: error)
            lastError = purchaseError
            readiness = .degraded(
                message: purchaseError.errorDescription ?? "Entitlement refresh failed."
            )
        }

        applyStatus(computeStatus())
    }

    public func loadOfferings() async {
        configureIfNeeded()

        if let currentOffering {
            availablePlans = Self.resolveAvailablePlans(
                plans: configuration.plans,
                offering: currentOffering,
                offeringsError: nil
            )
            return
        }

        var offeringsError: Error?
        do {
            currentOffering = try await commerceClient.loadOffering()
        } catch {
            currentOffering = nil
            offeringsError = error
        }

        availablePlans = Self.resolveAvailablePlans(
            plans: configuration.plans,
            offering: currentOffering,
            offeringsError: offeringsError
        )
    }

    public func startTrial() async {
        clearCommerceFeedback()
        guard status.canStartTrial else {
            return
        }
        guard case .time(_, startsOn: .explicit) = configuration.trialPolicy else {
            return
        }

        defaults.set(now(), forKey: configuration.storageKeys.trialStartedAt)
        applyStatus(computeStatus())
    }

    public func recordUsage(eventID: String) {
        guard case .usage(let configuredEventID, _) = configuration.trialPolicy,
              configuredEventID == eventID,
              status.isPro == false,
              status.isActive else {
            return
        }

        usageMeter.record(eventID: eventID)
        applyStatus(computeStatus())
    }

    public func usage(for eventID: String) -> Int {
        usageMeter.usage(for: eventID)
    }

    public func purchase(planID: String) async throws {
        configureIfNeeded()
        clearCommerceFeedback()
        guard let plan = plan(for: planID) else {
            throw CommercePurchaseError.unknown("Unknown plan id: \(planID)")
        }

        purchaseInProgressPlanID = plan.id
        defer { purchaseInProgressPlanID = nil }

        do {
            let snapshot = try await commerceClient.purchase(plan.commercePlan)
            lastError = nil
            entitlementSnapshot = snapshot
            readiness = .ready
            applyStatus(computeStatus())

            if !status.isPro {
                let didUnlock = await refreshEntitlementStateAfterTransaction()
                if !didUnlock {
                    throw CommercePurchaseError.activationPending
                }
            }

            if status.isPro {
                commerceFeedback = .purchaseSucceeded
            }
        } catch {
            let purchaseError = CommercePurchaseError(error: error)
            lastError = purchaseError
            commerceFeedback = purchaseError == .purchaseCancelled ? nil : .error(purchaseError)
            throw purchaseError
        }
    }

    public func restorePurchases() async throws {
        configureIfNeeded()
        clearCommerceFeedback()
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            let snapshot = try await commerceClient.restorePurchases()
            lastError = nil
            entitlementSnapshot = snapshot
            readiness = .ready
            applyStatus(computeStatus())

            if !status.isPro {
                if snapshot != nil {
                    let didUnlock = await refreshEntitlementStateAfterTransaction()
                    if !didUnlock {
                        throw CommercePurchaseError.activationPending
                    }
                } else {
                    commerceFeedback = .noActivePurchase
                }
            }

            if status.isPro {
                commerceFeedback = .restoreSucceeded
            }
        } catch {
            let purchaseError = CommercePurchaseError(error: error)
            lastError = purchaseError
            commerceFeedback = purchaseError == .purchaseCancelled ? nil : .error(purchaseError)
            throw purchaseError
        }
    }

    public func planProduct(for planID: String) -> KikiAccessPlanProduct {
        availablePlans.first(where: { $0.id == planID })
            ?? configuration.plans.first(where: { $0.id == planID }).map { KikiAccessPlanProduct.fallback(for: $0) }
            ?? KikiAccessPlanProduct.fallback(for: defaultPlan)
    }

#if DEBUG
    public func setDebugProAccessOverride(_ mode: KikiAccessDebugMode) {
        defaults.set(mode.rawValue, forKey: configuration.storageKeys.debugProAccessOverride)
        debugProAccessOverride = mode
        clearCommerceFeedback()
        applyStatus(computeStatus())
    }

    public func clearDebugProAccessOverride() {
        defaults.removeObject(forKey: configuration.storageKeys.debugProAccessOverride)
        debugProAccessOverride = nil
        clearCommerceFeedback()
        applyStatus(computeStatus())
    }
#endif

    public static func makeAvailablePlans(
        plans: [KikiAccessPlan],
        packageMetadata: [String: KikiAccessPlanPackageMetadata]?,
        offeringsAttempted: Bool = false
    ) -> [KikiAccessPlanProduct] {
        plans.map { plan in
            let fallback = KikiAccessPlanProduct.fallback(
                for: plan,
                isAvailable: packageMetadata == nil && !offeringsAttempted
            )

            guard let metadata = packageMetadata?[plan.id] else {
                return fallback
            }

            return KikiAccessPlanProduct(
                plan: plan,
                displayPrice: metadata.displayPrice,
                billingDetail: metadata.billingDetail,
                isAvailable: metadata.isAvailable
            )
        }
    }

    private var defaultPlan: KikiAccessPlan {
        Self.defaultPlan(in: configuration)
    }

    private func plan(for planID: String) -> KikiAccessPlan? {
        configuration.plans.first { $0.id == planID }
    }

    private func clearCommerceFeedback() {
        commerceFeedback = nil
    }

    private func refreshEntitlementStateAfterTransaction() async -> Bool {
        for attempt in 1...Constants.transactionRefreshAttempts {
            do {
                entitlementSnapshot = try await commerceClient.refreshEntitlement()
                readiness = .ready
                applyStatus(computeStatus())

                if status.isPro {
                    return true
                }
            } catch {
                lastError = CommercePurchaseError(error: error)
            }

            if attempt < Constants.transactionRefreshAttempts {
                try? await Task.sleep(nanoseconds: Constants.transactionRefreshDelayNanoseconds)
            }
        }

        return false
    }

    private func computeStatus() -> KikiAccessState {
        Self.computeStatus(
            configuration: configuration,
            entitlementSnapshot: entitlementSnapshot,
            defaults: defaults,
            usageMeter: usageMeter,
            now: now
        )
    }

    private func applyStatus(_ newStatus: KikiAccessState) {
        status = newStatus
        scheduleExpirationIfNeeded()
    }

    private func scheduleExpirationIfNeeded() {
        expirationTask?.cancel()
        expirationTask = nil

        guard case .trial(.time(_, let expiresAt)) = status else {
            return
        }

        let delay = max(0, expiresAt.timeIntervalSince(now()))
        expirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else {
                return
            }
            self.applyStatus(self.computeStatus())
        }
    }

    private static func computeStatus(
        configuration: KikiAccessConfiguration,
        entitlementSnapshot: CommerceEntitlement?,
        defaults: UserDefaults,
        usageMeter: any KikiUsageMeter,
        now: () -> Date
    ) -> KikiAccessState {
#if DEBUG
        if let debugProAccessOverride = readDebugProAccessOverride(defaults: defaults, keys: configuration.storageKeys) {
            switch debugProAccessOverride {
            case .live:
                break
            case .notPro:
                return .notStarted
            case .trial:
                let expiresAt = now().addingTimeInterval(2 * 86_400)
                return .trial(.time(daysRemaining: 2, expiresAt: expiresAt))
            case .pro:
                return .pro(
                    plan: defaultPlan(in: configuration),
                    entitlement: debugEntitlement(configuration: configuration)
                )
            }
        }
#endif

        if let entitlementSnapshot {
            let plan = plan(for: entitlementSnapshot, in: configuration.plans)
                ?? defaultPlan(in: configuration)
            return .pro(plan: plan, entitlement: entitlementSnapshot)
        }

        switch configuration.trialPolicy {
        case .disabled:
            return .expired
        case .usage(let eventID, let limit):
            let safeLimit = max(0, limit)
            let used = max(0, usageMeter.usage(for: eventID))
            guard used < safeLimit else {
                return .expired
            }
            return .trial(.usage(eventID: eventID, used: used, limit: safeLimit))
        case .time(let duration, let startsOn):
            guard let trialStartedAt = defaults.object(
                forKey: configuration.storageKeys.trialStartedAt
            ) as? Date else {
                switch startsOn {
                case .explicit:
                    return .notStarted
                case .automatic:
                    return .notStarted
                }
            }

            let expiresAt = trialStartedAt.addingTimeInterval(duration)
            let remaining = expiresAt.timeIntervalSince(now())

            if remaining > 0 {
                return .trial(
                    .time(
                        daysRemaining: max(1, Int(ceil(remaining / 86_400))),
                        expiresAt: expiresAt
                    )
                )
            }

            return .expired
        }
    }

    private static func startAutoTrialIfNeeded(
        configuration: KikiAccessConfiguration,
        defaults: UserDefaults,
        now: () -> Date
    ) {
        guard case .time(_, startsOn: .automatic) = configuration.trialPolicy,
              defaults.object(forKey: configuration.storageKeys.trialStartedAt) == nil else {
            return
        }

        defaults.set(now(), forKey: configuration.storageKeys.trialStartedAt)
    }

    private static func plan(for entitlement: CommerceEntitlement, in plans: [KikiAccessPlan]) -> KikiAccessPlan? {
        plans.first { plan in
            plan.commercePlan == entitlement.plan
        }
    }

    private static func defaultPlan(in configuration: KikiAccessConfiguration) -> KikiAccessPlan {
        configuration.plans.first(where: { $0.id == configuration.defaultPlanID })
            ?? configuration.plans.first
            ?? KikiAccessPlan(
                id: "lifetime",
                commercePlan: .lifetime,
                title: "Lifetime",
                fallbackDisplayPrice: "",
                billingDetail: "once",
                subtitle: "Pay once, use forever"
            )
    }

    private static func packageMetadata(
        plans: [KikiAccessPlan],
        from offering: CommerceOffering?
    ) -> [String: KikiAccessPlanPackageMetadata]? {
        guard let offering, !offering.isEmpty else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: offering.products.compactMap { product in
            guard let plan = plans.first(where: { $0.commercePlan == product.plan }) else {
                return nil
            }

            return (
                plan.id,
                KikiAccessPlanPackageMetadata(
                    displayPrice: product.displayPrice,
                    billingDetail: plan.billingDetail,
                    isAvailable: product.isAvailable
                )
            )
        })
    }

    private static func resolveAvailablePlans(
        plans: [KikiAccessPlan],
        offering: CommerceOffering?,
        offeringsError: Error?
    ) -> [KikiAccessPlanProduct] {
        let purchaseError = offeringsError.map(CommercePurchaseError.init(error:))
        let shouldKeepFallbackAvailable = purchaseError == .network

        return makeAvailablePlans(
            plans: plans,
            packageMetadata: packageMetadata(plans: plans, from: offering),
            offeringsAttempted: !shouldKeepFallbackAvailable
        )
    }

#if DEBUG
    private static func readDebugProAccessOverride(
        defaults: UserDefaults,
        keys: KikiAccessStorageKeys
    ) -> KikiAccessDebugMode? {
        guard let rawValue = defaults.string(forKey: keys.debugProAccessOverride) else {
            return nil
        }
        return KikiAccessDebugMode(rawValue: rawValue)
    }

    private static func debugEntitlement(configuration: KikiAccessConfiguration) -> CommerceEntitlement {
        let plan = defaultPlan(in: configuration)
        return CommerceEntitlement(
            plan: plan.commercePlan,
            productIdentifier: "debug.\(plan.id)",
            entitlementIdentifier: "debug.pro",
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: nil
        )
    }
#endif
}

public struct KikiAccessPlanPackageMetadata: Equatable, Sendable {
    public let displayPrice: String
    public let billingDetail: String
    public let isAvailable: Bool

    public init(displayPrice: String, billingDetail: String, isAvailable: Bool) {
        self.displayPrice = displayPrice
        self.billingDetail = billingDetail
        self.isAvailable = isAvailable
    }
}
