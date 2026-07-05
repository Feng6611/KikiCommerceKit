import Foundation

public struct RevenueCatConfiguration: Sendable {
    public let apiKey: String
    public let offeringIdentifier: String
    public let requestTimeoutNanoseconds: UInt64
    public let invalidReceiptRecoveryDelayNanoseconds: UInt64
    public let allowsTestAPIKeyInRelease: Bool
    public let showStoreMessagesAutomatically: Bool

    public init(
        apiKey: String,
        offeringIdentifier: String = "default",
        requestTimeoutNanoseconds: UInt64 = 4_000_000_000,
        invalidReceiptRecoveryDelayNanoseconds: UInt64 = 1_000_000_000,
        allowsTestAPIKeyInRelease: Bool = false,
        showStoreMessagesAutomatically: Bool = true
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.offeringIdentifier = offeringIdentifier
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.invalidReceiptRecoveryDelayNanoseconds = invalidReceiptRecoveryDelayNanoseconds
        self.allowsTestAPIKeyInRelease = allowsTestAPIKeyInRelease
        self.showStoreMessagesAutomatically = showStoreMessagesAutomatically
    }

    public static func standardPro(
        apiKey: String,
        offeringIdentifier: String = "default"
    ) -> Self {
        Self(
            apiKey: apiKey,
            offeringIdentifier: offeringIdentifier
        )
    }

    public static func standardProFromInfoDictionary(
        apiKeyInfoDictionaryKey: String,
        bundle: Bundle = .main,
        offeringIdentifier: String = "default"
    ) -> Self {
        let apiKey = (bundle.object(forInfoDictionaryKey: apiKeyInfoDictionaryKey) as? String) ?? ""

        return standardPro(
            apiKey: apiKey,
            offeringIdentifier: offeringIdentifier
        )
    }
}
