import Foundation

public struct KikiProPaywallCopy: Equatable, Sendable {
    public let title: String
    public let proSubtitle: String
    public let trialSubtitle: String
    public let expiredSubtitle: String
    public let notStartedSubtitle: String
    public let features: [String]

    public init(
        title: String = "Choose your plan",
        proSubtitle: String = "All features are unlocked.",
        trialSubtitle: String = "Choose a plan or continue with your trial.",
        expiredSubtitle: String = "Your trial has ended. Upgrade to keep using Pro.",
        notStartedSubtitle: String = "Choose a plan or start your free trial.",
        features: [String] = []
    ) {
        self.title = title
        self.proSubtitle = proSubtitle
        self.trialSubtitle = trialSubtitle
        self.expiredSubtitle = expiredSubtitle
        self.notStartedSubtitle = notStartedSubtitle
        self.features = features
    }
}

public enum KikiProPaywallPresentationContext: Equatable, Sendable {
    case settings
    case onboarding
}
