import Foundation
import KikiCommerceCore
import KikiCommercePresentation
import SwiftUI
import Testing

@MainActor
struct KikiProPaywallViewsTests {
    @Test("Status card and sheet are constructible")
    func statusCardAndSheetAreConstructible() {
        let manager = makeManager()
        var selectedPlanID = "supporterLifetime"

        _ = KikiProPaywallSheet(manager: manager, context: .settings)
        _ = KikiProPaywallSheet(manager: manager, context: .onboarding)
        _ = KikiProUpgradeCard(
            status: manager.status,
            products: manager.availablePlans,
            selectedPlanID: .init(
                get: { selectedPlanID },
                set: { selectedPlanID = $0 }
            )
        )
        _ = KikiProStatusCard(status: manager.status)
    }

    private func makeManager() -> KikiProAccessManager {
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
            commerceClient: NoopCommerceClient(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }
}

@MainActor
private final class NoopCommerceClient: CommerceClient {
    var cachedEntitlement: CommerceEntitlement?
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)?

    func configureIfNeeded() {}
    func refreshEntitlement() async throws -> CommerceEntitlement? { nil }
    func loadOffering() async throws -> CommerceOffering? { nil }
    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? { nil }
    func restorePurchases() async throws -> CommerceEntitlement? { nil }
}
