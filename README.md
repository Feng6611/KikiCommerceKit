# KikiCommerceKit

Cross-product commerce + paywall toolkit for KikiCommerce Mac apps. Three layered targets:

- **KikiCommerceCore** — pure abstractions: `CommerceClient` protocol, `CommerceConfiguration`, `CommerceEntitlement`, `CommercePlan`, `KikiProAccessManager`, `KikiProAccessConfiguration`, paywall copy/layout models. No RevenueCat, no UI.
- **KikiRevenueCat** — RevenueCat-backed `CommerceClient` adapter (`RevenueCatCommerceClient`), legacy paid-app entitlement source (App Store receipt parsing + `AppTransaction` grandfathering), RevenueCat → `CommercePurchaseError` mapper, convenience init for `KikiProAccessManager`.
- **KikiCommercePresentation** — SwiftUI views (`KikiProPaywallSheet`, `KikiProUpgradeCard`, `KikiProStatusCard`) built on `KikiPaywall` from `Kiki_mackit`.

## Layering

```
KikiCommercePresentation ──┐
                           ├──> KikiCommerceCore
KikiRevenueCat ────────────┘            │
       │                                │
       └─> RevenueCat SDK               └─> Kiki_mackit (for KikiPaywall, presentation only)
```

Apps depending only on `KikiCommerceCore` can pass an in-process `CommerceClient` stub; apps wanting RevenueCat link `KikiRevenueCat`; apps wanting the default sheet link `KikiCommercePresentation`.

## Quick start

```swift
import KikiCommerceCore
import KikiRevenueCat

let configuration = KikiProAccessConfiguration(
    plans: [...],
    defaultPlanID: "lifetime",
    commerceConfiguration: .standardPro(
        apiKey: "appl_xxx",
        bundleIdentifier: "com.example.MyApp"
    ),
    storageKeys: .prefixed("com.example.MyApp.Pro")
)

let manager = KikiProAccessManager(configuration: configuration)
manager.configureIfNeeded()
```

## Tests

```sh
swift test
```
