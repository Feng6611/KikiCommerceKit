import Foundation
import StoreKit
import os
import KikiCommerceCore

@MainActor
protocol LegacyPaidAppEntitlementProviding: AnyObject {
    var cachedLegacyEntitlement: CommerceEntitlement? { get }

    func refreshLegacyEntitlement(configuration: CommerceConfiguration, logger: Logger) async -> CommerceEntitlement?
}

@MainActor
final class LegacyPaidAppEntitlementSource: LegacyPaidAppEntitlementProviding {
    private(set) var cachedLegacyEntitlement: CommerceEntitlement?

    func refreshLegacyEntitlement(configuration: CommerceConfiguration, logger: Logger) async -> CommerceEntitlement? {
        guard configuration.legacyPaidApp.isEnabled else {
            cachedLegacyEntitlement = nil
            return nil
        }

        if #available(macOS 13.0, iOS 16.0, *) {
            do {
                if let entitlement = Self.entitlementIfGrandfathered(
                    from: try await AppTransaction.shared,
                    configuration: configuration
                ) {
                    cachedLegacyEntitlement = entitlement
                    logger.notice("Detected legacy paid-app entitlement from AppTransaction.")
                    return entitlement
                }
            } catch {
                logger.error("Failed to load AppTransaction for legacy paid-app entitlement: \(error.localizedDescription)")
            }
        }

        return cachedLegacyEntitlement
    }

    @available(macOS 13.0, iOS 16.0, *)
    private static func entitlementIfGrandfathered(
        from verificationResult: StoreKit.VerificationResult<StoreKit.AppTransaction>,
        configuration: CommerceConfiguration
    ) -> CommerceEntitlement? {
        guard case .verified(let transaction) = verificationResult else {
            return nil
        }

        return entitlementIfGrandfathered(
            originalAppVersion: transaction.originalAppVersion,
            originalPurchaseDate: transaction.originalPurchaseDate,
            configuration: configuration
        )
    }

    static func entitlementIfGrandfathered(
        originalAppVersion: String,
        originalPurchaseDate: Date?,
        configuration: CommerceConfiguration
    ) -> CommerceEntitlement? {
        guard isGrandfathered(
            originalAppVersion: originalAppVersion,
            configuration: configuration.legacyPaidApp
        ) else {
            return nil
        }

        return makeLegacyEntitlement(
            configuration: configuration,
            originalPurchaseDate: originalPurchaseDate
        )
    }

    private static func isGrandfathered(
        originalAppVersion: String,
        configuration: LegacyPaidAppConfiguration
    ) -> Bool {
        originalAppVersion.compare(configuration.cutoffOriginalAppVersion, options: .numeric) == .orderedAscending
    }

    private static func makeLegacyEntitlement(
        configuration: CommerceConfiguration,
        originalPurchaseDate: Date?
    ) -> CommerceEntitlement {
        let legacyConfiguration = configuration.legacyPaidApp
        let productIdentifier = legacyConfiguration.productIdentifier
            ?? configuration.productIdentifiers[legacyConfiguration.mapsToPlan]
            ?? "legacy-paid-app"

        return CommerceEntitlement(
            plan: legacyConfiguration.mapsToPlan,
            productIdentifier: productIdentifier,
            entitlementIdentifier: legacyConfiguration.entitlementIdentifier,
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: originalPurchaseDate
        )
    }
}
