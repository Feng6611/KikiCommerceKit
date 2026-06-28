import Foundation
import KikiCommerceCore
import Testing

@MainActor
struct KikiProAccessManagerTests {
    @Test("Explicit trial starts as not started")
    func explicitTrialStartsAsNotStarted() {
        let fixture = Fixture()
        let manager = fixture.makeManager()

        #expect(manager.status == .notStarted)
        #expect(!manager.hasCompletedOnboarding)
    }

    @Test("Starting trial stores start date and completes onboarding")
    func startTrialStoresStartDateAndCompletesOnboarding() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let fixture = Fixture(now: { start })
        let manager = fixture.makeManager()

        await manager.startTrial()

        #expect(fixture.defaults.object(forKey: fixture.storageKeys.trialStartedAt) as? Date == start)
        #expect(manager.hasCompletedOnboarding)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: start.addingTimeInterval(Fixture.trialDuration)))
    }

    @Test("Expired trial resolves to expired")
    func expiredTrialResolvesToExpired() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(Fixture.trialDuration + 1)
        let fixture = Fixture(now: { now })
        fixture.defaults.set(start, forKey: fixture.storageKeys.trialStartedAt)

        let manager = fixture.makeManager()

        #expect(manager.status == .expired)
    }

    @Test("Purchase success unlocks pro and preserves purchase date")
    func purchaseSuccessUnlocksProAndPreservesPurchaseDate() async throws {
        let purchaseDate = Date(timeIntervalSince1970: 2_000)
        let entitlement = Fixture.entitlement(plan: .lifetime, originalPurchaseDate: purchaseDate)
        let client = MockCommerceClient()
        client.purchaseEntitlement = entitlement
        let fixture = Fixture(client: client)
        let manager = fixture.makeManager()

        try await manager.purchase(planID: "supporterLifetime")

        guard case .pro(let plan, let snapshot) = manager.status else {
            Issue.record("Expected pro status")
            return
        }
        #expect(plan.id == "supporterLifetime")
        #expect(snapshot.originalPurchaseDate == purchaseDate)
        #expect(manager.hasCompletedOnboarding)
    }

    @Test("Purchase without entitlement retries refresh and reports activation pending")
    func purchaseWithoutEntitlementRetriesRefreshAndReportsActivationPending() async {
        let client = MockCommerceClient()
        client.purchaseEntitlement = nil
        client.fetchedEntitlement = nil
        let fixture = Fixture(client: client)
        let manager = fixture.makeManager()

        await #expect(throws: CommercePurchaseError.activationPending) {
            try await manager.purchase(planID: "supporterLifetime")
        }
        #expect(client.refreshEntitlementCallCount == KikiProAccessManager.Constants.transactionRefreshAttempts)
        #expect(manager.paywallErrorMessage == CommercePurchaseError.activationPending.errorDescription)
    }

    @Test("Restore without entitlement shows no active purchase")
    func restoreWithoutEntitlementShowsNoActivePurchase() async throws {
        let client = MockCommerceClient()
        client.restoreEntitlement = nil
        let fixture = Fixture(client: client)
        let manager = fixture.makeManager()

        try await manager.restorePurchases()

        #expect(manager.status == .notStarted)
        #expect(manager.paywallErrorMessage == fixture.configuration.messages.noActivePurchase)
    }

    @Test("Network offering error keeps fallback plans available")
    func networkOfferingErrorKeepsFallbackAvailable() async {
        let client = MockCommerceClient()
        client.offeringsError = CommercePurchaseError.network
        let fixture = Fixture(client: client)
        let manager = fixture.makeManager()

        await manager.loadOfferings()

        #expect(manager.availablePlans.allSatisfy { $0.isAvailable })
        #expect(manager.availablePlans.map(\.displayPrice) == ["$5.99", "$10.99"])
    }

    @Test("Non-network offering error marks fallback plans unavailable")
    func nonNetworkOfferingErrorMarksFallbackUnavailable() async {
        let client = MockCommerceClient()
        client.offeringsError = CommercePurchaseError.invalidCredentials
        let fixture = Fixture(client: client)
        let manager = fixture.makeManager()

        await manager.loadOfferings()

        #expect(manager.availablePlans.allSatisfy { !$0.isAvailable })
    }

#if DEBUG
    @Test("Debug override paid unpaid and clear")
    func debugOverridePaidUnpaidAndClear() {
        let fixture = Fixture()
        let manager = fixture.makeManager()

        manager.setDebugProAccessOverride(true)
        #expect(manager.debugProAccessOverride == true)
        #expect(manager.status.isPro)
        #expect(manager.hasCompletedOnboarding)

        manager.setDebugProAccessOverride(false)
        #expect(manager.debugProAccessOverride == false)
        #expect(manager.status == .expired)

        manager.clearDebugProAccessOverride()
        #expect(manager.debugProAccessOverride == nil)
        #expect(manager.status == .notStarted)
    }
#endif
}

@MainActor
final class MockCommerceClient: CommerceClient {
    var cachedEntitlement: CommerceEntitlement?
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)?

    var currentOffering: CommerceOffering?
    var fetchedEntitlement: CommerceEntitlement?
    var purchaseEntitlement: CommerceEntitlement?
    var restoreEntitlement: CommerceEntitlement?
    var offeringsError: Error?
    var entitlementError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var configureCallCount = 0
    var loadOfferingCallCount = 0
    var refreshEntitlementCallCount = 0

    func configureIfNeeded() {
        configureCallCount += 1
    }

    func refreshEntitlement() async throws -> CommerceEntitlement? {
        refreshEntitlementCallCount += 1

        if let entitlementError {
            throw entitlementError
        }

        return fetchedEntitlement
    }

    func loadOffering() async throws -> CommerceOffering? {
        loadOfferingCallCount += 1

        if let offeringsError {
            throw offeringsError
        }

        return currentOffering
    }

    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        if let purchaseError {
            throw purchaseError
        }

        return purchaseEntitlement
    }

    func restorePurchases() async throws -> CommerceEntitlement? {
        if let restoreError {
            throw restoreError
        }

        return restoreEntitlement
    }
}

@MainActor
final class Fixture {
    static let trialDuration: TimeInterval = 2 * 24 * 60 * 60

    let defaults: UserDefaults
    let storageKeys: KikiProAccessStorageKeys
    let configuration: KikiProAccessConfiguration
    let client: MockCommerceClient
    let now: () -> Date

    init(
        client: MockCommerceClient? = nil,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) {
        let suiteName = "KikiCommerceCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        self.defaults = defaults
        self.storageKeys = .prefixed("KikiCommerceCoreTests.Pro")
        self.client = client ?? MockCommerceClient()
        self.now = now
        self.configuration = KikiProAccessConfiguration(
            plans: [
                KikiProPlan(
                    id: "lifetime",
                    commercePlan: .yearly,
                    title: "Lifetime",
                    fallbackDisplayPrice: "$5.99",
                    billingDetail: "one-time purchase",
                    subtitle: "Unlock all features"
                ),
                KikiProPlan(
                    id: "supporterLifetime",
                    commercePlan: .lifetime,
                    title: "Supporter Lifetime",
                    fallbackDisplayPrice: "$10.99",
                    billingDetail: "one-time purchase",
                    subtitle: "Support development",
                    badge: "Recommended"
                )
            ],
            defaultPlanID: "supporterLifetime",
            commerceConfiguration: CommerceConfiguration(
                apiKey: "test",
                entitlementIdentifier: "pro",
                productIdentifiers: [
                    .yearly: "dev.kkuk.test.pro.yearly",
                    .lifetime: "dev.kkuk.test.pro.lifetime"
                ]
            ),
            trialPolicy: .explicitStart(duration: Self.trialDuration),
            storageKeys: storageKeys
        )
    }

    func makeManager() -> KikiProAccessManager {
        KikiProAccessManager(
            configuration: configuration,
            defaults: defaults,
            commerceClient: client,
            now: now
        )
    }

    static func entitlement(
        plan: CommercePlan,
        originalPurchaseDate: Date? = nil
    ) -> CommerceEntitlement {
        CommerceEntitlement(
            plan: plan,
            productIdentifier: "dev.kkuk.test.pro.\(plan.rawValue)",
            entitlementIdentifier: "pro",
            expirationDate: nil,
            originalPurchaseDate: originalPurchaseDate
        )
    }
}
