import Foundation

public struct LegacyPaidAppConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let cutoffOriginalAppVersion: String
    public let entitlementIdentifier: String
    public let mapsToPlan: CommercePlan
    public let productIdentifier: String?

    private init(
        isEnabled: Bool,
        cutoffOriginalAppVersion: String,
        entitlementIdentifier: String,
        mapsToPlan: CommercePlan,
        productIdentifier: String?
    ) {
        self.isEnabled = isEnabled
        self.cutoffOriginalAppVersion = cutoffOriginalAppVersion
        self.entitlementIdentifier = entitlementIdentifier
        self.mapsToPlan = mapsToPlan
        self.productIdentifier = productIdentifier
    }

    public static let disabled = Self(
        isEnabled: false,
        cutoffOriginalAppVersion: "",
        entitlementIdentifier: "",
        mapsToPlan: .lifetime,
        productIdentifier: nil
    )

    public static func grandfatheredPaidApp(
        cutoffOriginalAppVersion: String,
        entitlementIdentifier: String,
        mapsToPlan: CommercePlan = .lifetime,
        productIdentifier: String? = nil
    ) -> Self {
        Self(
            isEnabled: true,
            cutoffOriginalAppVersion: cutoffOriginalAppVersion,
            entitlementIdentifier: entitlementIdentifier,
            mapsToPlan: mapsToPlan,
            productIdentifier: productIdentifier
        )
    }
}
