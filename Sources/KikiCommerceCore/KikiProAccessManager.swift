import Combine
import Foundation

@MainActor
public final class KikiProAccessManager: ObservableObject {
    public enum Constants {
        public static let transactionRefreshAttempts = 3
        public static let transactionRefreshDelayNanoseconds: UInt64 = 750_000_000
    }

    @Published public private(set) var status: KikiProAccessStatus
    @Published public private(set) var availablePlans: [KikiProPlanProduct]
    @Published public private(set) var lastError: CommercePurchaseError?
    @Published public private(set) var purchaseInProgressPlanID: String?
    @Published public private(set) var isRestoringPurchases = false
    @Published public private(set) var paywallErrorMessage: String?
    @Published public private(set) var paywallSuccessMessage: String?
#if DEBUG
    @Published public private(set) var debugProAccessOverride: Bool?
#endif

    public var currentEntitlementSnapshot: CommerceEntitlement? {
        entitlementSnapshot
    }

    public let configuration: KikiProAccessConfiguration

    private let defaults: UserDefaults
    private let commerceClient: any CommerceClient
    private let now: () -> Date

    private var entitlementSnapshot: CommerceEntitlement?
    private var currentOffering: CommerceOffering?
    private var hasConfigured = false
    private var expirationTask: Task<Void, Never>?

    public init(
        configuration: KikiProAccessConfiguration,
        defaults: UserDefaults = .standard,
        commerceClient: any CommerceClient,
        now: @escaping () -> Date = Date.init
    ) {
        let client = commerceClient
        self.configuration = configuration
        self.defaults = defaults
        self.commerceClient = client
        self.now = now
        self.entitlementSnapshot = client.cachedEntitlement
        self.currentOffering = nil
        self.availablePlans = Self.makeAvailablePlans(
            plans: configuration.plans,
            packageMetadata: nil
        )
        self.lastError = nil
        self.purchaseInProgressPlanID = nil
        self.paywallErrorMessage = nil
        self.paywallSuccessMessage = nil
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

        do {
            entitlementSnapshot = try await commerceClient.refreshEntitlement()
            lastError = nil
        } catch {
            lastError = CommercePurchaseError(error: error)
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
        clearPaywallMessages()
        guard status.canStartTrial else {
            return
        }
        guard case .explicitStart = configuration.trialPolicy else {
            return
        }

        defaults.set(now(), forKey: configuration.storageKeys.trialStartedAt)
        applyStatus(computeStatus())
    }

    public func purchase(planID: String) async throws {
        configureIfNeeded()
        clearPaywallMessages()
        guard let plan = plan(for: planID) else {
            throw CommercePurchaseError.unknown("Unknown plan id: \(planID)")
        }

        purchaseInProgressPlanID = plan.id
        defer { purchaseInProgressPlanID = nil }

        do {
            let snapshot = try await commerceClient.purchase(plan.commercePlan)
            lastError = nil
            entitlementSnapshot = snapshot
            applyStatus(computeStatus())

            if !status.isPro {
                let didUnlock = await refreshEntitlementStateAfterTransaction()
                if !didUnlock {
                    throw CommercePurchaseError.activationPending
                }
            }

            if status.isPro {
                paywallSuccessMessage = configuration.messages.purchaseSuccess
            }
        } catch {
            let purchaseError = CommercePurchaseError(error: error)
            lastError = purchaseError
            paywallErrorMessage = purchaseError == .purchaseCancelled ? nil : purchaseError.errorDescription
            paywallSuccessMessage = nil
            throw purchaseError
        }
    }

    public func restorePurchases() async throws {
        configureIfNeeded()
        clearPaywallMessages()
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            let snapshot = try await commerceClient.restorePurchases()
            lastError = nil
            entitlementSnapshot = snapshot
            applyStatus(computeStatus())

            if !status.isPro {
                if snapshot != nil {
                    let didUnlock = await refreshEntitlementStateAfterTransaction()
                    if !didUnlock {
                        throw CommercePurchaseError.activationPending
                    }
                } else {
                    paywallErrorMessage = configuration.messages.noActivePurchase
                }
            }

            if status.isPro {
                paywallSuccessMessage = configuration.messages.restoreSuccess
            }
        } catch {
            let purchaseError = CommercePurchaseError(error: error)
            lastError = purchaseError
            paywallErrorMessage = purchaseError == .purchaseCancelled ? nil : purchaseError.errorDescription
            paywallSuccessMessage = nil
            throw purchaseError
        }
    }

    public func planProduct(for planID: String) -> KikiProPlanProduct {
        availablePlans.first(where: { $0.id == planID })
            ?? configuration.plans.first(where: { $0.id == planID }).map { KikiProPlanProduct.fallback(for: $0) }
            ?? KikiProPlanProduct.fallback(for: defaultPlan)
    }

#if DEBUG
    public var debugProAccessToggleIsOn: Bool {
        debugProAccessOverride ?? status.isPro
    }

    public var debugProAccessOverrideDisplayName: String {
        guard let debugProAccessOverride else {
            return "Off"
        }

        return debugProAccessOverride ? "Paid" : "Unpaid"
    }

    public func setDebugProAccessOverride(_ isPro: Bool) {
        defaults.set(isPro, forKey: configuration.storageKeys.debugProAccessOverride)
        debugProAccessOverride = isPro
        clearPaywallMessages()
        applyStatus(computeStatus())
    }

    public func clearDebugProAccessOverride() {
        defaults.removeObject(forKey: configuration.storageKeys.debugProAccessOverride)
        debugProAccessOverride = nil
        clearPaywallMessages()
        applyStatus(computeStatus())
    }
#endif

    public static func makeAvailablePlans(
        plans: [KikiProPlan],
        packageMetadata: [String: KikiProPlanPackageMetadata]?,
        offeringsAttempted: Bool = false
    ) -> [KikiProPlanProduct] {
        plans.map { plan in
            let fallback = KikiProPlanProduct.fallback(
                for: plan,
                isAvailable: packageMetadata == nil && !offeringsAttempted
            )

            guard let metadata = packageMetadata?[plan.id] else {
                return fallback
            }

            return KikiProPlanProduct(
                plan: plan,
                displayPrice: metadata.displayPrice,
                billingDetail: metadata.billingDetail,
                isAvailable: metadata.isAvailable
            )
        }
    }

    private var defaultPlan: KikiProPlan {
        configuration.plans.first(where: { $0.id == configuration.defaultPlanID })
            ?? configuration.plans.first
            ?? KikiProPlan(
                id: "lifetime",
                commercePlan: .lifetime,
                title: "Lifetime",
                fallbackDisplayPrice: "",
                billingDetail: "once",
                subtitle: "Pay once, use forever"
            )
    }

    private func plan(for planID: String) -> KikiProPlan? {
        configuration.plans.first { $0.id == planID }
    }

    private func clearPaywallMessages() {
        paywallErrorMessage = nil
        paywallSuccessMessage = nil
    }

    private func refreshEntitlementStateAfterTransaction() async -> Bool {
        for attempt in 1...Constants.transactionRefreshAttempts {
            do {
                entitlementSnapshot = try await commerceClient.refreshEntitlement()
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

    private func computeStatus() -> KikiProAccessStatus {
        Self.computeStatus(
            configuration: configuration,
            entitlementSnapshot: entitlementSnapshot,
            defaults: defaults,
            now: now
        )
    }

    private func applyStatus(_ newStatus: KikiProAccessStatus) {
        status = newStatus
        scheduleExpirationIfNeeded()
    }

    private func scheduleExpirationIfNeeded() {
        expirationTask?.cancel()
        expirationTask = nil

        guard case .trial(_, let expiresAt) = status else {
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
        configuration: KikiProAccessConfiguration,
        entitlementSnapshot: CommerceEntitlement?,
        defaults: UserDefaults,
        now: () -> Date
    ) -> KikiProAccessStatus {
#if DEBUG
        if let debugProAccessOverride = readDebugProAccessOverride(defaults: defaults, keys: configuration.storageKeys) {
            return debugProAccessOverride ? .pro(
                plan: configuration.plans.first(where: { $0.id == configuration.defaultPlanID })
                    ?? configuration.plans.first!,
                entitlement: debugEntitlement(configuration: configuration)
            ) : .expired
        }
#endif

        if let entitlementSnapshot,
           let plan = plan(for: entitlementSnapshot, in: configuration.plans) {
            return .pro(plan: plan, entitlement: entitlementSnapshot)
        }

        guard let duration = configuration.trialPolicy.duration else {
            return .expired
        }

        guard let trialStartedAt = defaults.object(forKey: configuration.storageKeys.trialStartedAt) as? Date else {
            switch configuration.trialPolicy {
            case .explicitStart:
                return .notStarted
            case .autoStart:
                return .notStarted
            case .disabled:
                return .expired
            }
        }

        let expiresAt = trialStartedAt.addingTimeInterval(duration)
        let remaining = expiresAt.timeIntervalSince(now())

        if remaining > 0 {
            return .trial(daysRemaining: max(1, Int(ceil(remaining / 86_400))), expiresAt: expiresAt)
        }

        return .expired
    }

    private static func startAutoTrialIfNeeded(
        configuration: KikiProAccessConfiguration,
        defaults: UserDefaults,
        now: () -> Date
    ) {
        guard case .autoStart = configuration.trialPolicy,
              defaults.object(forKey: configuration.storageKeys.trialStartedAt) == nil else {
            return
        }

        defaults.set(now(), forKey: configuration.storageKeys.trialStartedAt)
    }

    private static func plan(for entitlement: CommerceEntitlement, in plans: [KikiProPlan]) -> KikiProPlan? {
        plans.first { plan in
            plan.commercePlan == entitlement.plan
        }
    }

    private static func packageMetadata(
        plans: [KikiProPlan],
        from offering: CommerceOffering?
    ) -> [String: KikiProPlanPackageMetadata]? {
        guard let offering, !offering.isEmpty else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: offering.products.compactMap { product in
            guard let plan = plans.first(where: { $0.commercePlan == product.plan }) else {
                return nil
            }

            return (
                plan.id,
                KikiProPlanPackageMetadata(
                    displayPrice: product.displayPrice,
                    billingDetail: plan.billingDetail,
                    isAvailable: product.isAvailable
                )
            )
        })
    }

    private static func resolveAvailablePlans(
        plans: [KikiProPlan],
        offering: CommerceOffering?,
        offeringsError: Error?
    ) -> [KikiProPlanProduct] {
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
        keys: KikiProAccessStorageKeys
    ) -> Bool? {
        guard defaults.object(forKey: keys.debugProAccessOverride) != nil else {
            return nil
        }

        return defaults.bool(forKey: keys.debugProAccessOverride)
    }

    private static func debugEntitlement(configuration: KikiProAccessConfiguration) -> CommerceEntitlement {
        let plan = configuration.plans.first(where: { $0.id == configuration.defaultPlanID })
            ?? configuration.plans.first!
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

public struct KikiProPlanPackageMetadata: Equatable, Sendable {
    public let displayPrice: String
    public let billingDetail: String
    public let isAvailable: Bool

    public init(displayPrice: String, billingDetail: String, isAvailable: Bool) {
        self.displayPrice = displayPrice
        self.billingDetail = billingDetail
        self.isAvailable = isAvailable
    }
}
