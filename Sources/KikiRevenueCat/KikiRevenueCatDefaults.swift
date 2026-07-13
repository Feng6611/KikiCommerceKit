import Foundation
import KikiCommerceCore

extension KikiAccessManager {
    public convenience init(
        configuration: KikiAccessConfiguration,
        revenueCatConfiguration: RevenueCatConfiguration,
        defaults: UserDefaults = .standard,
        usageMeter: (any KikiUsageMeter)? = nil,
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
            usageMeter: usageMeter,
            now: now
        )
    }
}
