import XCTest
@testable import KikiCommerceCore

final class CommerceConfigurationTests: XCTestCase {
    func testStandardProBuildsProductIdentifiersFromBundleIdentifier() throws {
        let configuration = CommerceConfiguration.standardPro(
            bundleIdentifier: "com.example.MyApp"
        )

        XCTAssertEqual(configuration.entitlementIdentifier, "pro")
        XCTAssertEqual(configuration.entitlementMatchingPolicy, .configuredEntitlementOrProductOnly)
        XCTAssertEqual(try configuration.productIdentifier(for: .yearly), "com.example.MyApp.pro.yearly")
        XCTAssertEqual(try configuration.productIdentifier(for: .lifetime), "com.example.MyApp.pro.lifetime")
    }

    func testExplicitConfigurationKeepsSkuValues() throws {
        let configuration = CommerceConfiguration(
            entitlementIdentifier: "pro",
            productIdentifiers: [
                .yearly: "yearly.sku",
                .lifetime: "lifetime.sku"
            ]
        )

        XCTAssertEqual(try configuration.productIdentifier(for: .yearly), "yearly.sku")
        XCTAssertEqual(try configuration.productIdentifier(for: .lifetime), "lifetime.sku")
    }

    func testMissingProductIdentifierThrows() {
        let configuration = CommerceConfiguration(
            entitlementIdentifier: "pro",
            productIdentifiers: [.yearly: "yearly.sku"]
        )

        XCTAssertThrowsError(try configuration.productIdentifier(for: .lifetime)) { error in
            XCTAssertEqual(error as? CommercePurchaseError, .productIdentifierMissing(.lifetime))
        }
    }
}
