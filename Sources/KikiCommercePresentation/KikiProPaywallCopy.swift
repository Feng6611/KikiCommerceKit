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
        title: String = String(localized: "Choose your plan", bundle: .main, comment: "Paywall header when the user has not chosen a plan yet."),
        proSubtitle: String = String(localized: "All features are unlocked.", bundle: .main, comment: "Paywall subtitle when the user already owns Pro."),
        trialSubtitle: String = String(localized: "Choose a plan or continue with your trial.", bundle: .main, comment: "Paywall subtitle during an active trial."),
        expiredSubtitle: String = String(localized: "Your trial has ended. Upgrade to keep using Pro.", bundle: .main, comment: "Paywall subtitle when the trial has expired."),
        notStartedSubtitle: String = String(localized: "Choose a plan or start your free trial.", bundle: .main, comment: "Paywall subtitle before the user starts the trial."),
        features: [String] = [],
        purchaseActionTitle: String = String(localized: "Unlock forever", bundle: .main, comment: "One-time-purchase CTA on the paywall."),
        trialActionTitle: String = String(localized: "Start free trial", bundle: .main, comment: "Trial-start CTA on the paywall."),
        restoreActionTitle: String = String(localized: "Restore purchases", bundle: .main, comment: "Restore-existing-purchase link on the paywall."),
        doneActionTitle: String = String(localized: "Done", bundle: .main, comment: "Dismiss-paywall CTA."),
        loadingOptionsMessage: String = String(localized: "Loading purchase options…", bundle: .main, comment: "Progress message while StoreKit resolves products."),
        unavailableOptionsMessage: String = String(localized: "Purchase options are unavailable right now. Try again later or restore an existing purchase.", bundle: .main, comment: "Fallback message when products can't be loaded."),
        purchaseSuccessMessage: String = String(localized: "Purchase successful. Pro unlocked.", bundle: .main, comment: "Success feedback after a completed purchase."),
        restoreSuccessMessage: String = String(localized: "Purchase restored.", bundle: .main, comment: "Success feedback after a completed restore."),
        noActivePurchaseMessage: String = String(localized: "No active purchase found on this account.", bundle: .main, comment: "Feedback when a restore finishes with nothing to restore."),
        purchaseErrorMessage: String = String(localized: "The purchase couldn't be completed.", bundle: .main, comment: "Generic purchase-failure message; raw provider error is logged separately."),
        restoreErrorMessage: String = String(localized: "Purchases couldn't be restored.", bundle: .main, comment: "Generic restore-failure message."),
        trialErrorMessage: String = String(localized: "The free trial couldn't be started.", bundle: .main, comment: "Generic trial-start-failure message.")
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
