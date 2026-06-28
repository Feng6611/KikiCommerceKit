import Foundation
import KikiCommerceCore
import RevenueCat

extension CommercePurchaseError {
    public static func from(revenueCatError error: Error) -> CommercePurchaseError {
        if let commerceError = error as? CommercePurchaseError {
            return commerceError
        }

        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           let errorCode = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch errorCode {
            case .purchaseCancelledError:
                return .purchaseCancelled
            case .purchaseNotAllowedError:
                return .purchaseNotAllowed
            case .invalidReceiptError:
                return .invalidReceipt
            case .productNotAvailableForPurchaseError:
                return .productUnavailable
            case .networkError:
                return .network
            case .invalidCredentialsError:
                return .invalidCredentials
            case .configurationError:
                return .notConfigured
            default:
                return .unknown(nsError.localizedDescription)
            }
        }

        return .unknown(nsError.localizedDescription)
    }
}
