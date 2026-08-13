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

    /// Ceiling on the StoreKit lookup below. Callers pass the same value the
    /// RevenueCat requests use, so one refresh cannot take longer than the
    /// budget the app already agreed to.
    private let timeoutNanoseconds: UInt64

    init(timeoutNanoseconds: UInt64 = 4_000_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func refreshLegacyEntitlement(configuration: CommerceConfiguration, logger: Logger) async -> CommerceEntitlement? {
        guard configuration.legacyPaidApp.isEnabled else {
            cachedLegacyEntitlement = nil
            return nil
        }

        if #available(macOS 13.0, iOS 16.0, *) {
            do {
                if let entitlement = Self.entitlementIfGrandfathered(
                    from: try await appTransaction(logger: logger),
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

    /// `AppTransaction.shared` reaches the App Store, and on a copy with no
    /// receipt — a development build, a Mac signed into a sandbox account, a
    /// machine that is offline — it can take seconds or never return at all.
    /// It runs first in the entitlement refresh, so an unbounded wait here
    /// holds the whole refresh, and the app sits on "checking purchases" for
    /// as long as StoreKit feels like taking. The RevenueCat call after it was
    /// already bounded; this is the one that was not.
    @available(macOS 13.0, iOS 16.0, *)
    private func appTransaction(logger: Logger) async throws -> StoreKit.VerificationResult<StoreKit.AppTransaction> {
        try await withThrowingTaskGroup(
            of: StoreKit.VerificationResult<StoreKit.AppTransaction>.self
        ) { [timeoutNanoseconds] group in
            group.addTask {
                try await AppTransaction.shared
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw CommercePurchaseError.network
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                logger.error("Timed out waiting for AppTransaction with no result.")
                throw CommercePurchaseError.network
            }

            return result
        }
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
