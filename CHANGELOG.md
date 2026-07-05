# Changelog

## Unreleased — 0.1.0

### Added
- Initial release. Merges the former `RevenueCatCommerceKit` package and the `KikiCommerce` target from `Kiki_mackit` into a single layered package with three libraries:
  - `KikiCommerceCore` — abstractions: `CommerceClient`, `CommerceConfiguration`, `CommerceEntitlement`, `CommercePlan`, `CommercePurchaseError`, `LegacyPaidAppConfiguration`, `KikiProAccessManager`, `KikiProAccessConfiguration`, `KikiProPaywallCopy/Layout`. No RevenueCat dependency. `CommerceConfiguration` carries only generic StoreKit-level config (entitlement identifier, product identifiers, matching policy, legacy paid app, log); RevenueCat-specific config lives in `KikiRevenueCat.RevenueCatConfiguration`.
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
- `CommerceConfiguration` no longer carries RevenueCat-specific fields (`apiKey`, `offeringIdentifier`, `allowsTestAPIKeyInRelease`, `showStoreMessagesAutomatically`, `requestTimeoutNanoseconds`, `invalidReceiptRecoveryDelayNanoseconds`). These moved to `KikiRevenueCat.RevenueCatConfiguration`. `CommerceConfiguration.standardPro(apiKey:bundleIdentifier:...)` is now `RevenueCatConfiguration.standardPro(apiKey:bundleIdentifier:)` plus `CommerceConfiguration.standardPro(bundleIdentifier:)`.
- `RevenueCatCommerceClient.init` now takes both `configuration: CommerceConfiguration` and `revenueCatConfiguration: RevenueCatConfiguration`.
- `KikiProAccessManager` convenience init in `KikiRevenueCat` now takes `revenueCatConfiguration:` explicitly: `KikiProAccessManager(configuration:revenueCatConfiguration:defaults:now:)`.
- `KikiProAccessManager` no longer tracks onboarding completion. `hasCompletedOnboarding`, `shouldShowOnboarding`, and `completeOnboardingWithoutTrial()` are gone; `KikiProAccessStorageKeys` dropped the `hasCompletedOnboarding` key. Apps should route onboarding completion through Kit's `OnboardingFlow.CompletionStore` and observe `manager.status` for purchase/restore success.
- `KikiCommercePresentation` is now a thin adapter (97 lines, down from 587). `KikiProUpgradeCard` and `KikiProStatusCard` are removed; apps build status UI from Kit's atoms. `KikiProExternalLinks` and `KikiProPaywallLayout` are removed (Kit's presets handle layout). `KikiProPaywallCopy` and `KikiProPaywallPresentationContext` moved from Core to Presentation. `KikiProPaywallCopy` dropped `proCardTitle` / `proCardSubtitle` (no longer needed without `KikiProUpgradeCard`).
