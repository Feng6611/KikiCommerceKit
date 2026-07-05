import Foundation

public enum CommercePurchaseError: Error, Equatable, Sendable {
    case notConfigured
    case invalidConfiguration(String)
    case offeringUnavailable
    case packageNotFound(CommercePlan)
    case productIdentifierMissing(CommercePlan)
    case purchaseCancelled
    case purchaseNotAllowed
    case activationPending
    case invalidReceipt
    case network
    case invalidCredentials
    case productUnavailable
    case unknown(String)
}

extension CommercePurchaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Purchases are not configured yet."
        case .invalidConfiguration(let message):
            message
        case .offeringUnavailable:
            "No products are currently available."
        case .packageNotFound(let plan):
            "The \(plan.rawValue) product is not available in the current offering."
        case .productIdentifierMissing(let plan):
            "The \(plan.rawValue) product identifier is missing."
        case .purchaseCancelled:
            "The purchase was cancelled."
        case .purchaseNotAllowed:
            "Purchases are not allowed on this device."
        case .activationPending:
            "Purchase completed, but access is still syncing."
        case .invalidReceipt:
            "The App Store did not finish syncing this purchase yet."
        case .network:
            "A network connection is required to load purchases."
        case .invalidCredentials:
            "The commerce API key is invalid."
        case .productUnavailable:
            "This product is not available for purchase."
        case .unknown(let message):
            message
        }
    }
}

extension CommercePurchaseError {
    public init(error: Error) {
        if let commerceError = error as? CommercePurchaseError {
            self = commerceError
            return
        }

        self = .unknown((error as NSError).localizedDescription)
    }
}
