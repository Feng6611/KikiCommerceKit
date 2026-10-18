import Foundation

public struct RevenueCatConfiguration: Sendable {
    public let apiKey: String
    public let offeringIdentifier: String
    public let requestTimeoutNanoseconds: UInt64
    public let invalidReceiptRecoveryDelayNanoseconds: UInt64
    public let allowsTestAPIKeyInRelease: Bool
    public let showStoreMessagesAutomatically: Bool
    /// Sent as RevenueCat's `$posthogUserId` attribute after configuration, so the
    /// RevenueCat PostHog integration lands on the host's analytics identity.
    /// It does not change the RevenueCat app user ID. Empty means none.
    public let postHogUserID: String?

    public init(
        apiKey: String,
        offeringIdentifier: String = "default",
        requestTimeoutNanoseconds: UInt64 = 4_000_000_000,
        invalidReceiptRecoveryDelayNanoseconds: UInt64 = 1_000_000_000,
        allowsTestAPIKeyInRelease: Bool = false,
        showStoreMessagesAutomatically: Bool = true,
        postHogUserID: String? = nil
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.offeringIdentifier = offeringIdentifier
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.invalidReceiptRecoveryDelayNanoseconds = invalidReceiptRecoveryDelayNanoseconds
        self.allowsTestAPIKeyInRelease = allowsTestAPIKeyInRelease
        self.showStoreMessagesAutomatically = showStoreMessagesAutomatically
        let trimmedPostHogUserID = postHogUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.postHogUserID = trimmedPostHogUserID.isEmpty ? nil : trimmedPostHogUserID
    }

    public static func standardPro(
        apiKey: String,
        offeringIdentifier: String = "default",
        postHogUserID: String? = nil
    ) -> Self {
        Self(
            apiKey: apiKey,
            offeringIdentifier: offeringIdentifier,
            postHogUserID: postHogUserID
        )
    }

    public static func standardProFromInfoDictionary(
        apiKeyInfoDictionaryKey: String,
        bundle: Bundle = .main,
        offeringIdentifier: String = "default",
        postHogUserID: String? = nil
    ) -> Self {
        let apiKey = (bundle.object(forInfoDictionaryKey: apiKeyInfoDictionaryKey) as? String) ?? ""

        return standardPro(
            apiKey: apiKey,
            offeringIdentifier: offeringIdentifier,
            postHogUserID: postHogUserID
        )
    }
}
