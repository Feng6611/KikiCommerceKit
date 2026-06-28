import Foundation
import KikiCommerceCore
import RevenueCat
import XCTest
@testable import KikiRevenueCat

final class CommercePurchaseErrorTests: XCTestCase {
    func testRevenueCatConfigurationErrorsMapToNotConfigured() {
        let error = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.configurationError.rawValue
        )

        XCTAssertEqual(CommercePurchaseError.from(revenueCatError: error), .notConfigured)
    }

    func testRevenueCatInvalidReceiptErrorsMapToInvalidReceipt() {
        let error = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.invalidReceiptError.rawValue
        )

        XCTAssertEqual(CommercePurchaseError.from(revenueCatError: error), .invalidReceipt)
    }

    func testNonRevenueCatDomainsDoNotGetRemappedByRawCodeAlone() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: RevenueCat.ErrorCode.configurationError.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Cocoa failure"]
        )

        XCTAssertEqual(CommercePurchaseError.from(revenueCatError: error), .unknown("Cocoa failure"))
    }
}
