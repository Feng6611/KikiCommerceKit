import Foundation

@MainActor
public protocol CommerceClient: AnyObject {
    var cachedEntitlement: CommerceEntitlement? { get }
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)? { get set }

    func configureIfNeeded()
    func refreshEntitlement() async throws -> CommerceEntitlement?
    func loadOffering() async throws -> CommerceOffering?
    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement?
    /// Purchases `plan` from the surface named `placement` (for example
    /// "settings"), so the store can attribute the sale. Clients without
    /// attribution ignore the placement.
    func purchase(_ plan: CommercePlan, placement: String?) async throws -> CommerceEntitlement?
    func restorePurchases() async throws -> CommerceEntitlement?
}

public extension CommerceClient {
    func purchase(_ plan: CommercePlan, placement: String?) async throws -> CommerceEntitlement? {
        try await purchase(plan)
    }
}
