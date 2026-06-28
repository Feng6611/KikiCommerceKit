# Changelog

## Unreleased — 0.1.0

### Added
- Initial release. Merges the former `RevenueCatCommerceKit` package and the `KikiCommerce` target from `Kiki_mackit` into a single layered package with three libraries:
  - `KikiCommerceCore` — abstractions: `CommerceClient`, `CommerceConfiguration`, `CommerceEntitlement`, `CommercePlan`, `CommercePurchaseError`, `LegacyPaidAppConfiguration`, `KikiProAccessManager`, `KikiProAccessConfiguration`, `KikiProPaywallCopy/Layout`. No RevenueCat dependency.
  - `KikiRevenueCat` — `RevenueCatCommerceClient`, `RevenueCatSnapshotMapper`, `LegacyPaidAppEntitlementSource` (App Store receipt parsing + `AppTransaction` grandfathering), `CommercePurchaseError.from(revenueCatError:)`, and a convenience `KikiProAccessManager.init(configuration:defaults:now:)` that wires up `RevenueCatCommerceClient`.
  - `KikiCommercePresentation` — `KikiProPaywallSheet`, `KikiProUpgradeCard`, `KikiProStatusCard` built on `KikiPaywall`.

### Migration from prior packages
- `RevenueCatCommerceKit` is deprecated and replaced by this package. Imports change as follows:
  - `import RevenueCatCommerceKit` → split into `import KikiCommerceCore` (most types) plus `import KikiRevenueCat` (RevenueCat adapter types).
  - `CommercePurchaseError(error:)` for RevenueCat NSError mapping → `CommercePurchaseError.from(revenueCatError:)` from `KikiRevenueCat`. The Core `CommercePurchaseError(error:)` initializer only pass-through `CommercePurchaseError` and falls back to `.unknown(localizedDescription)`.
- The `KikiCommerce` target inside `Kiki_mackit` is removed. Replace `import KikiCommerce` with `import KikiCommerceCore` (manager + models) and `import KikiCommercePresentation` (paywall views).
