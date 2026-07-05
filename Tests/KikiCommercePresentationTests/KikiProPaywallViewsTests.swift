import Foundation
import KikiCommerceCore
@testable import KikiCommercePresentation
import SwiftUI
import Testing

@MainActor
struct KikiProPaywallViewsTests {
    @Test("Sheet is constructible in both contexts")
    func sheetIsConstructibleInBothContexts() {
        let manager = makeManager()

        _ = KikiProPaywallSheet(manager: manager, context: .settings)
        _ = KikiProPaywallSheet(manager: manager, context: .onboarding)
    }

    @Test("Settings keeps purchase primary and exposes trial plus restore")
    func settingsActionPolicy() {
        let policy = KikiProPaywallActionPolicy.resolve(
            status: .notStarted,
            context: .settings
        )

        #expect(policy.primary == .purchase)
        #expect(policy.secondary == [.startTrial, .restore])
    }

    @Test("Onboarding keeps trial primary and restore secondary")
    func onboardingActionPolicy() {
        let policy = KikiProPaywallActionPolicy.resolve(
            status: .notStarted,
            context: .onboarding
        )

        #expect(policy.primary == .startTrial)
        #expect(policy.secondary == [.restore])
    }

    @Test("Entitled state dismisses without transaction actions")
    func entitledActionPolicy() {
        let manager = makeManager()
        let plan = manager.configuration.plans[0]
        let status = KikiProAccessStatus.pro(
            plan: plan,
            entitlement: CommerceEntitlement(
                plan: plan.commercePlan,
                productIdentifier: "dev.kkuk.test.pro.lifetime",
                entitlementIdentifier: "pro",
                expirationDate: nil
            )
        )

        let policy = KikiProPaywallActionPolicy.resolve(
            status: status,
            context: .settings
        )

        #expect(policy.primary == .dismiss)
        #expect(policy.secondary.isEmpty)
    }

    @Test("Workflow loads offerings before presentation")
    func workflowLoadsOfferings() async {
        let client = NoopCommerceClient()
        client.offering = CommerceOffering(
            identifier: "current",
            products: [
                CommerceProduct(
                    plan: .yearly,
                    productIdentifier: "dev.kkuk.test.pro.yearly",
                    displayPrice: "$6.99",
                    isAvailable: true
                )
            ]
        )
        let manager = makeManager(client: client)
        let workflow = KikiProPaywallWorkflow(manager: manager)

        await workflow.loadOfferings()

        #expect(client.loadOfferingCallCount == 1)
        #expect(manager.availablePlans.first?.displayPrice == "$6.99")
    }

    @Test("Workflow reports completion only after successful access changes")
    func workflowReportsSuccessfulCompletion() async {
        let client = NoopCommerceClient()
        client.purchaseEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "dev.kkuk.test.pro.lifetime",
            entitlementIdentifier: "pro",
            expirationDate: nil
        )
        let manager = makeManager(client: client)
        let workflow = KikiProPaywallWorkflow(manager: manager)

        let didComplete = await workflow.purchase(planID: "supporterLifetime")

        #expect(didComplete)
        #expect(manager.status.isPro)
    }

    @Test("Workflow reports completion after restore unlocks access")
    func workflowReportsRestoreCompletion() async {
        let client = NoopCommerceClient()
        client.restoreEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "dev.kkuk.test.pro.lifetime",
            entitlementIdentifier: "pro",
            expirationDate: nil
        )
        let manager = makeManager(client: client)
        let workflow = KikiProPaywallWorkflow(manager: manager)

        let didComplete = await workflow.restorePurchases()

        #expect(didComplete)
        #expect(manager.status.isPro)
    }

    @Test("Workflow reports completion after trial starts")
    func workflowReportsTrialCompletion() async {
        let manager = makeManager()
        let workflow = KikiProPaywallWorkflow(manager: manager)

        let didComplete = await workflow.startTrial()

        #expect(didComplete)
        #expect(manager.status.isActive)
    }

    @Test("Workflow keeps purchase failures visible")
    func workflowKeepsPurchaseFailuresVisible() async {
        let client = NoopCommerceClient()
        client.purchaseError = CommercePurchaseError.network
        let manager = makeManager(client: client)
        let workflow = KikiProPaywallWorkflow(manager: manager)

        let didComplete = await workflow.purchase(planID: "supporterLifetime")

        #expect(didComplete == false)
        #expect(manager.commerceFeedback == .error(.network))
    }

    @Test("Paywall error copy is supplied by the host")
    func paywallErrorCopyIsHostOwned() {
        let copy = KikiProPaywallCopy(
            purchaseErrorMessage: "Please check your connection and try again."
        )

        #expect(copy.purchaseErrorMessage == "Please check your connection and try again.")
    }

    private func makeManager(client: NoopCommerceClient? = nil) -> KikiProAccessManager {
        let suiteName = "KikiCommercePresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let configuration = KikiProAccessConfiguration(
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
                entitlementIdentifier: "pro",
                productIdentifiers: [
                    .yearly: "dev.kkuk.test.pro.yearly",
                    .lifetime: "dev.kkuk.test.pro.lifetime"
                ]
            ),
            trialPolicy: .explicitStart(duration: 2 * 24 * 60 * 60),
            storageKeys: .prefixed("KikiCommercePresentationTests.Pro")
        )

        return KikiProAccessManager(
            configuration: configuration,
            defaults: defaults,
            commerceClient: client ?? NoopCommerceClient(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }
}

@MainActor
private final class NoopCommerceClient: CommerceClient {
    var cachedEntitlement: CommerceEntitlement?
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)?
    var offering: CommerceOffering?
    var purchaseEntitlement: CommerceEntitlement?
    var restoreEntitlement: CommerceEntitlement?
    var purchaseError: Error?
    var loadOfferingCallCount = 0

    func configureIfNeeded() {}
    func refreshEntitlement() async throws -> CommerceEntitlement? { nil }
    func loadOffering() async throws -> CommerceOffering? {
        loadOfferingCallCount += 1
        return offering
    }
    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        if let purchaseError {
            throw purchaseError
        }
        return purchaseEntitlement
    }
    func restorePurchases() async throws -> CommerceEntitlement? { restoreEntitlement }
}
