import Foundation

public enum CommerceEntitlementMatchingPolicy: Equatable, Sendable {
    case configuredEntitlementOrProductOnly
    case allowAnyActiveEntitlement
}

public struct CommerceConfiguration: Sendable {
    public let entitlementIdentifier: String
    public let productIdentifiers: [CommercePlan: String]
    public let entitlementMatchingPolicy: CommerceEntitlementMatchingPolicy
    public let legacyPaidApp: LegacyPaidAppConfiguration
    public let logSubsystem: String
    public let logCategory: String

    public init(
        entitlementIdentifier: String,
        productIdentifiers: [CommercePlan: String],
        entitlementMatchingPolicy: CommerceEntitlementMatchingPolicy = .configuredEntitlementOrProductOnly,
        legacyPaidApp: LegacyPaidAppConfiguration = .disabled,
        logSubsystem: String = Bundle.main.bundleIdentifier ?? "KikiCommerceCore",
        logCategory: String = "Commerce"
    ) {
        self.entitlementIdentifier = entitlementIdentifier
        self.productIdentifiers = productIdentifiers
        self.entitlementMatchingPolicy = entitlementMatchingPolicy
        self.legacyPaidApp = legacyPaidApp
        self.logSubsystem = logSubsystem
        self.logCategory = logCategory
    }

    public static func standardPro(
        bundleIdentifier: String,
        entitlementIdentifier: String = "pro",
        productSuffix: String = "pro"
    ) -> Self {
        Self(
            entitlementIdentifier: entitlementIdentifier,
            productIdentifiers: [
                .yearly: "\(bundleIdentifier).\(productSuffix).yearly",
                .lifetime: "\(bundleIdentifier).\(productSuffix).lifetime"
            ],
            logSubsystem: bundleIdentifier
        )
    }

    public static func standardProFromInfoDictionary(
        bundle: Bundle = .main,
        entitlementIdentifier: String = "pro",
        productSuffix: String = "pro"
    ) -> Self {
        let bundleIdentifier = bundle.bundleIdentifier ?? "KikiCommerceCore"
        return standardPro(
            bundleIdentifier: bundleIdentifier,
            entitlementIdentifier: entitlementIdentifier,
            productSuffix: productSuffix
        )
    }

    public func productIdentifier(for plan: CommercePlan) throws -> String {
        guard let productIdentifier = productIdentifiers[plan], !productIdentifier.isEmpty else {
            throw CommercePurchaseError.productIdentifierMissing(plan)
        }

        return productIdentifier
    }
}
