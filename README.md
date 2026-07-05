# KikiCommerceKit

Cross-product commerce + paywall toolkit for Kiki Mac apps. Three layered targets:

- **KikiCommerceCore** — provider-neutral access workflow: `CommerceClient`, commerce models/configuration, trial state, `KikiProAccessManager`, and app-supplied plan metadata. No RevenueCat and no SwiftUI.
- **KikiRevenueCat** — RevenueCat-backed `CommerceClient`, verified `AppTransaction` legacy grandfathering, RevenueCat error/snapshot mapping, and the convenience RevenueCat initializer for `KikiProAccessManager`.
- **KikiCommercePresentation** — `KikiProPaywallSheet`, which owns reusable offering/action orchestration and adapts access state to the display-only `KikiPaywall` presets from `Kiki_mackit`.

## Layering

```
KikiCommercePresentation ─────> KikiCommerceCore
          │
          └───────────────────> KikiPaywall (Kiki_mackit)

KikiRevenueCat ───────────────> KikiCommerceCore
          │
          └───────────────────> RevenueCat SDK
```

Apps depending only on `KikiCommerceCore` can pass an in-process `CommerceClient` stub; apps wanting RevenueCat link `KikiRevenueCat`; apps wanting the default sheet link `KikiCommercePresentation`.

## Contracts

- `CommercePlan` is an open string-backed identity. `.yearly` and `.lifetime`
  are conveniences, not an exhaustive catalog; apps may use IDs such as
  `monthly`, `supporterLifetime`, or any provider-neutral SKU role.
- Trial policy is `.time(duration:startsOn:)`, `.usage(eventID:limit:)`, or
  `.disabled`. The app decides what counts as one usage event and calls
  `recordUsage(eventID:)`.
- `KikiProAccessManager` emits semantic `KikiCommerceFeedback`; it does not own
  paywall strings. `KikiCommercePresentation` maps feedback through
  caller-supplied `KikiProPaywallCopy`.
- `KikiProPaywallSheet` owns reusable offerings and transaction orchestration.
  The app owns copy, footer links, product configuration, feature gates, and
  post-finish routing.

## Quick start

```swift
import KikiCommerceCore
import KikiRevenueCat

let commerceConfiguration = CommerceConfiguration(
    entitlementIdentifier: "pro",
    productIdentifiers: [
        CommercePlan("monthly"): "com.example.MyApp.pro.monthly",
        CommercePlan("supporterLifetime"): "com.example.MyApp.pro.supporter"
    ]
)
let accessConfiguration = KikiProAccessConfiguration(
    plans: [...],
    defaultPlanID: "supporterLifetime",
    commerceConfiguration: commerceConfiguration,
    trialPolicy: .explicitStart(duration: 2 * 24 * 60 * 60),
    storageKeys: .prefixed("com.example.MyApp.Pro")
)
let revenueCatConfiguration = RevenueCatConfiguration(
    apiKey: "appl_xxx",
    offeringIdentifier: "default"
)
let manager = KikiProAccessManager(
    configuration: accessConfiguration,
    revenueCatConfiguration: revenueCatConfiguration
)
manager.configureIfNeeded()
```

During coordinated local development this package and the reference app may
point to the same adjacent `../Kiki_mackit` checkout so SwiftPM sees one package
identity. A release must use the tagged HTTPS Kiki_mackit dependency.

## Tests

```sh
swift test
```
