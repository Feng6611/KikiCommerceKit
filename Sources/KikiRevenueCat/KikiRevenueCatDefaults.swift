import Foundation
import KikiCommerceCore

extension KikiProAccessManager {
    public convenience init(
        configuration: KikiProAccessConfiguration,
        revenueCatConfiguration: RevenueCatConfiguration,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        let client = RevenueCatCommerceClient(
            configuration: configuration.commerceConfiguration,
            revenueCatConfiguration: revenueCatConfiguration
        )
        self.init(
            configuration: configuration,
            defaults: defaults,
            commerceClient: client,
            now: now
        )
    }
}
