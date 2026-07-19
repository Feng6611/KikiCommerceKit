# KikiCommerceKit

Optional, product-neutral Commerce Feature Kit for Kiki macOS apps.

## Products

- `KikiCommerceCore`: `KikiAccessManager`, readiness, open plan catalog,
  time/usage/disabled trials, purchase/restore protocols, and access state.
- `KikiRevenueCat`: RevenueCat transport and legacy paid-App entitlement mapping.
- `KikiCommercePresentation`: standard Settings/Onboarding paywall workflow that
  renders Base Kit `KikiPaywallPresentation` presets.
- `KikiCommerceTesting`: deterministic in-memory Commerce client for tests,
  previews, and generated paid Starter projects.

New code uses the product-neutral `KikiAccess*` names. The earlier `KikiPro*`
surface remains as deprecated type aliases so existing App storage and source
migrations can proceed independently.

## Readiness

`KikiAccessManager.status` may be computed from cached entitlement and local
trial state immediately. `readiness` separately reports whether the first remote
entitlement refresh is authoritative:

- `idle` / `loading`: do not make automatic onboarding or paywall decisions;
- `ready`: automatic presentation may use the current status;
- `degraded`: cached active access may continue, but absence of an entitlement
  is not proof that a user is unpaid.

Apps still decide what product event counts as usage and record it only after
that product action succeeds.

Cross-product commerce + paywall toolkit for Kiki Mac apps. Three layered targets:

- **KikiCommerceCore** — provider-neutral access workflow: `CommerceClient`, commerce models/configuration, trial state, `KikiAccessManager`, and app-supplied plan metadata. No RevenueCat and no SwiftUI.
- **KikiRevenueCat** — RevenueCat-backed `CommerceClient`, verified `AppTransaction` legacy grandfathering, RevenueCat error/snapshot mapping, and the convenience RevenueCat initializer for `KikiAccessManager`.
- **KikiCommercePresentation** — `KikiAccessPaywallSheet`, which owns reusable offering/action orchestration and adapts access state to the display-only `KikiPaywall` presets from `Kiki_mackit`.

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
- `KikiAccessManager` emits semantic `KikiCommerceFeedback`; it does not own
  paywall strings. `KikiCommercePresentation` maps feedback through
  caller-supplied `KikiAccessPaywallCopy`.
- `KikiAccessPaywallSheet` owns reusable offerings and transaction orchestration.
  The app owns copy, footer links, product configuration, feature gates, and
  post-finish routing.

## Apple Sandbox and production

`KikiRevenueCat` does not select Apple Sandbox or Production from `#if DEBUG`.
For Apple-backed apps, both Debug and Release use the Apple app's public
RevenueCat SDK key (`appl_`). StoreKit and Apple receipts determine the
transaction environment:

- a valid Apple Development-signed Debug app talks to Apple Sandbox;
- TestFlight/App Store distribution follows Apple's receipt environment;
- an unsigned or ad-hoc app is not an Apple Sandbox proof;
- a local optimized Release build is not an App Store distribution artifact.

RevenueCat Test Store remains supported by the provider layer for products that
explicitly choose it, but it is an app-owned testing policy and is not the
default for Kiki workspace paid apps. Build-time key injection, rejecting
`test_` for Apple-only apps, code-sign verification, Bundle ID checks, and
archive/export checks belong to the Product App/Starter tooling rather than the
runtime Commerce Kit.

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
let accessConfiguration = KikiAccessConfiguration(
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
let manager = KikiAccessManager(
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
