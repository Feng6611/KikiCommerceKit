import Foundation
import KikiCommerceCore

@MainActor
public final class KikiInMemoryCommerceClient: CommerceClient {
    public var cachedEntitlement: CommerceEntitlement?
    public var entitlementDidChange: ((CommerceEntitlement?) -> Void)?

    public var refreshResult: Result<CommerceEntitlement?, CommercePurchaseError>
    public var offeringResult: Result<CommerceOffering?, CommercePurchaseError>
    public var restoreResult: Result<CommerceEntitlement?, CommercePurchaseError>
    public var purchaseResults: [CommercePlan: Result<CommerceEntitlement?, CommercePurchaseError>]

    public private(set) var configureCallCount = 0
    public private(set) var refreshCallCount = 0
    public private(set) var offeringCallCount = 0
    public private(set) var purchaseCallCount = 0
    public private(set) var restoreCallCount = 0

    public init(
        entitlement: CommerceEntitlement? = nil,
        offering: CommerceOffering? = nil
    ) {
        self.cachedEntitlement = entitlement
        self.refreshResult = .success(entitlement)
        self.offeringResult = .success(offering)
        self.restoreResult = .success(entitlement)
        self.purchaseResults = [:]
    }

    public func configureIfNeeded() {
        configureCallCount += 1
    }

    public func refreshEntitlement() async throws -> CommerceEntitlement? {
        refreshCallCount += 1
        let entitlement = try refreshResult.get()
        cachedEntitlement = entitlement
        return entitlement
    }

    public func loadOffering() async throws -> CommerceOffering? {
        offeringCallCount += 1
        return try offeringResult.get()
    }

    public func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        purchaseCallCount += 1
        let entitlement = try purchaseResults[plan, default: .success(nil)].get()
        send(entitlement: entitlement)
        return entitlement
    }

    public func restorePurchases() async throws -> CommerceEntitlement? {
        restoreCallCount += 1
        let entitlement = try restoreResult.get()
        send(entitlement: entitlement)
        return entitlement
    }

    public func send(entitlement: CommerceEntitlement?) {
        cachedEntitlement = entitlement
        entitlementDidChange?(entitlement)
    }
}
