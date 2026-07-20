# Changelog

## Unreleased

## 0.2.0 - 2026-07-20

Requires `Kiki_mackit` 0.9.0 for the new `KikiPaywallActionStyle`
API. The bump is minor rather than a patch because downstream apps
that rebuild against this release will see restore render as a
footer link rather than a bordered button — a visible UI change
though no API break.

### Changed

- Bumped `Kiki_mackit` exact dependency to `0.9.0`.
- `restoreAction` in `KikiAccessPaywallSheet` now sets
  `style: .footerLink`. Restore is a return path (not a conversion
  CTA), and Kiki 0.9.0 splits `.footerLink`-styled actions out of
  the primary button stack into a dot-separated link row inside the
  footer. Downstream apps get the cleaner CTA hierarchy without any
  code change on their side.

## 0.1.2 - 2026-07-19

### Fixed

- Paywall purchase/trial/restore/dismiss roles now carry stable identities
  through rebuilt presentation snapshots, preserving SwiftUI focus and diffing.
- Paywall failures now use operation-specific purchase, restore, and free-trial
  messages while keeping copy host-configurable.

## 0.1.1 - 2026-07-14

### Fixed

- Bumped the exact `Kiki_mackit` dependency to `0.8.1`, keeping CommerceKit
  compatible with the transparent rounded-window fix used by onboarding
  paywall sheets.

## 0.1.0 - 2026-07-14

### Added

- Product-neutral `KikiAccess*` public names with deprecated `KikiPro*`
  compatibility aliases.
- Explicit access readiness for safe first-launch routing and degraded offline
  behavior.
- `KikiCommerceTesting` with a deterministic in-memory Commerce client.

### Changed

- Commerce Presentation now exposes `KikiAccessPaywall*` names while continuing
  to render Base Kit paywall presets.

## Migration notes from the pre-release package

### Added
- Initial release. Merges the former `RevenueCatCommerceKit` package and the `KikiCommerce` target from `Kiki_mackit` into a single layered package with three libraries:
  - `KikiCommerceCore` — provider-neutral access workflow: `CommerceClient`, `CommerceConfiguration`, `CommerceEntitlement`, `CommercePlan`, `CommercePurchaseError`, `LegacyPaidAppConfiguration`, `KikiProAccessManager`, and `KikiProAccessConfiguration`. No RevenueCat or SwiftUI dependency. `CommerceConfiguration` carries only generic StoreKit-level config (entitlement identifier, product identifiers, matching policy, legacy paid app, log); RevenueCat-specific config lives in `KikiRevenueCat.RevenueCatConfiguration`.
  - `KikiRevenueCat` — `RevenueCatConfiguration`, `RevenueCatCommerceClient`, `RevenueCatSnapshotMapper`, `LegacyPaidAppEntitlementSource` (`AppTransaction` grandfathering only), `CommercePurchaseError.from(revenueCatError:)`, and a convenience `KikiProAccessManager.init(configuration:revenueCatConfiguration:defaults:now:)` that wires up `RevenueCatCommerceClient`.
  - `KikiCommercePresentation` — `KikiProPaywallSheet`, a thin adapter that maps `KikiProAccessManager` state to `KikiPaywallPresentation` and renders Kit's `KikiCompactPaywall` (settings context) or `KikiOnboardingPaywall` (onboarding context). No second paywall UI.

### Security
- Removed the local App Store receipt fallback (`LegacyAppStoreReceipt` / `LegacyAppStoreReceiptParser` / ASN.1 machinery). The CMS payload was decoded without verifying signer status or certificate chain, so a forged receipt would grant lifetime entitlement. Legacy paid-app grandfathering now relies solely on `AppTransaction.shared` (verified by StoreKit on macOS 13+). Direct-distribution legacy migration will be re-added with proper verification if needed when Command Reopen migrates.

### Migration from prior packages
- `RevenueCatCommerceKit` is deprecated and replaced by this package. Imports change as follows:
  - `import RevenueCatCommerceKit` → split into `import KikiCommerceCore` (most types) plus `import KikiRevenueCat` (RevenueCat adapter types).
  - `CommercePurchaseError(error:)` for RevenueCat NSError mapping → `CommercePurchaseError.from(revenueCatError:)` from `KikiRevenueCat`. The Core `CommercePurchaseError(error:)` initializer only pass-through `CommercePurchaseError` and falls back to `.unknown(localizedDescription)`.
- The `KikiCommerce` target inside `Kiki_mackit` is removed. Replace `import KikiCommerce` with `import KikiCommerceCore` (manager + models) and `import KikiCommercePresentation` (paywall views).

### Changed (vs. initial 0.1.0 commit)
- `CommerceConfiguration` no longer carries RevenueCat-specific fields (`apiKey`, `offeringIdentifier`, `allowsTestAPIKeyInRelease`, `showStoreMessagesAutomatically`, `requestTimeoutNanoseconds`, `invalidReceiptRecoveryDelayNanoseconds`). These moved to `KikiRevenueCat.RevenueCatConfiguration`. Configuration is now split between `RevenueCatConfiguration.standardPro(apiKey:)` and `CommerceConfiguration.standardPro(bundleIdentifier:)`.
- `RevenueCatCommerceClient.init` now takes both `configuration: CommerceConfiguration` and `revenueCatConfiguration: RevenueCatConfiguration`.
- `KikiProAccessManager` convenience init in `KikiRevenueCat` now takes `revenueCatConfiguration:` explicitly: `KikiProAccessManager(configuration:revenueCatConfiguration:defaults:now:)`.
- `KikiProAccessManager` no longer tracks onboarding completion. `hasCompletedOnboarding`, `shouldShowOnboarding`, and `completeOnboardingWithoutTrial()` are gone; `KikiProAccessStorageKeys` dropped the `hasCompletedOnboarding` key. Apps should route onboarding completion through Kit's `OnboardingFlow.CompletionStore` and observe `manager.status` for purchase/restore success.
- `KikiCommercePresentation` is now an orchestration adapter over Kit presets instead of a second paywall implementation. `KikiProUpgradeCard` and `KikiProStatusCard` are removed; apps build status UI from Kit's atoms. `KikiProExternalLinks` and `KikiProPaywallLayout` are removed (Kit's presets handle layout). `KikiProPaywallCopy` and `KikiProPaywallPresentationContext` moved from Core to Presentation. `KikiProPaywallCopy` dropped `proCardTitle` / `proCardSubtitle` (no longer needed without `KikiProUpgradeCard`).
- Restored the reusable paywall workflow contract after the preset migration: offerings load on presentation, unavailable plans cannot be purchased, purchase/restore/trial operations are serialized, manager feedback is rendered, and successful access changes complete the host flow.
- Entitled paywalls now use the generic dismiss action instead of presenting a misleading “Manage subscription” button wired to purchase.
- `CommercePlan` is now an open `RawRepresentable` string identity. The
  `.yearly` / `.lifetime` values remain conveniences, while catalogs can add
  monthly, multiple lifetime tiers, or other plans without changing Core.
- Trial policy now supports time-, usage-, and disabled modes. Usage trials use
  an injected `KikiUsageMeter`, and the app records semantically named events.
- Commerce Core now emits semantic `KikiCommerceFeedback`; paywall success,
  empty-restore, and error copy is supplied by
  `KikiCommercePresentation.KikiProPaywallCopy`.
- Paywall presentation accepts ordered Terms/Privacy/Support links and uses
  explicit context policies: Settings offers purchase/trial/restore;
  onboarding prioritizes trial; entitled state dismisses.
- Coordinated local integration uses the same adjacent Kiki_mackit checkout as the reference app, avoiding duplicate SwiftPM package identities. Release builds must switch both packages to the same tagged HTTPS version.
- Bumped `Kiki_mackit` exact-version pin to 0.7.1 to pick up the onboarding, settings, and paywall should-fix fixes.
