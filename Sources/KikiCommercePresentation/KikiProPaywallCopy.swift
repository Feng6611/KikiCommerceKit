import Foundation

public struct KikiAccessPaywallCopy: Equatable, Sendable {
    public let title: String
    public let proSubtitle: String
    public let trialSubtitle: String
    public let expiredSubtitle: String
    public let notStartedSubtitle: String
    public let features: [String]
    public let purchaseActionTitle: String
    public let trialActionTitle: String
    public let restoreActionTitle: String
    public let doneActionTitle: String
    public let loadingOptionsMessage: String
    public let unavailableOptionsMessage: String
    public let purchaseSuccessMessage: String
    public let restoreSuccessMessage: String
    public let noActivePurchaseMessage: String
    public let purchaseErrorMessage: String
    public let restoreErrorMessage: String
    public let trialErrorMessage: String

    public init(
        title: String = "Choose your plan",
        proSubtitle: String = "All features are unlocked.",
        trialSubtitle: String = "Choose a plan or continue with your trial.",
        expiredSubtitle: String = "Your trial has ended. Upgrade to keep using Pro.",
        notStartedSubtitle: String = "Choose a plan or start your free trial.",
        features: [String] = [],
        purchaseActionTitle: String = "Unlock forever",
        trialActionTitle: String = "Start free trial",
        restoreActionTitle: String = "Restore purchases",
        doneActionTitle: String = "Done",
        loadingOptionsMessage: String = "Loading purchase options...",
        unavailableOptionsMessage: String = "Purchase options are unavailable right now. Try again later or restore an existing purchase.",
        purchaseSuccessMessage: String = "Purchase successful. Pro unlocked.",
        restoreSuccessMessage: String = "Purchase restored.",
        noActivePurchaseMessage: String = "No active purchase found on this account.",
        purchaseErrorMessage: String = "Something went wrong. Please try again.",
        restoreErrorMessage: String = String(localized: "Purchases couldn’t be restored.", bundle: .main),
        trialErrorMessage: String = String(localized: "The free trial couldn’t be started.", bundle: .main)
    ) {
        self.title = title
        self.proSubtitle = proSubtitle
        self.trialSubtitle = trialSubtitle
        self.expiredSubtitle = expiredSubtitle
        self.notStartedSubtitle = notStartedSubtitle
        self.features = features
        self.purchaseActionTitle = purchaseActionTitle
        self.trialActionTitle = trialActionTitle
        self.restoreActionTitle = restoreActionTitle
        self.doneActionTitle = doneActionTitle
        self.loadingOptionsMessage = loadingOptionsMessage
        self.unavailableOptionsMessage = unavailableOptionsMessage
        self.purchaseSuccessMessage = purchaseSuccessMessage
        self.restoreSuccessMessage = restoreSuccessMessage
        self.noActivePurchaseMessage = noActivePurchaseMessage
        self.purchaseErrorMessage = purchaseErrorMessage
        self.restoreErrorMessage = restoreErrorMessage
        self.trialErrorMessage = trialErrorMessage
    }
}

/// Caller-owned account figures retained from the 0.2.1 public API.
public struct KikiAccessPaywallStat: Equatable, Identifiable, Sendable {
    public let id: String
    public let value: String
    public let label: String

    public init(id: String? = nil, value: String, label: String) {
        self.id = id ?? "\(value)\u{1F}\(label)"
        self.value = value
        self.label = label
    }
}

public struct KikiAccessPaywallLink: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL

    public init(id: String, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public enum KikiAccessPaywallContext: Equatable, Sendable {
    case settings
    case onboarding
}
