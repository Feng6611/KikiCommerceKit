import KikiCommerceCore
import KikiCommerceTesting
import Testing

@MainActor
struct KikiInMemoryCommerceClientTests {
    @Test("In-memory client publishes purchase entitlement")
    func purchasePublishesEntitlement() async throws {
        let plan = CommercePlan("monthly")
        let entitlement = CommerceEntitlement(
            plan: plan,
            productIdentifier: "example.monthly",
            entitlementIdentifier: "pro",
            expirationDate: nil
        )
        let client = KikiInMemoryCommerceClient()
        client.purchaseResults[plan] = .success(entitlement)
        var observed: CommerceEntitlement?
        client.entitlementDidChange = { observed = $0 }

        let result = try await client.purchase(plan)

        #expect(result == entitlement)
        #expect(observed == entitlement)
        #expect(client.cachedEntitlement == entitlement)
        #expect(client.purchaseCallCount == 1)
    }

    @Test("In-memory client exposes controlled failures")
    func controlledFailure() async {
        let client = KikiInMemoryCommerceClient()
        client.refreshResult = .failure(.network)

        await #expect(throws: CommercePurchaseError.network) {
            try await client.refreshEntitlement()
        }
    }
}
