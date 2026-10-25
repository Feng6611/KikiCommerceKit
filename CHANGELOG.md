# Changelog

## Unreleased

### Changed

- Carries forward 0.5.2, which was cut from 0.5.1 and is not in 0.6.0: the
  onboarding paywall makes "Start free trial" the primary action while a trial
  can still be started; Settings keeps purchase primary.

## 0.6.0 - 2026-10-24

Requires `Kiki_mackit` 0.12.0 (exact), which ships `KikiPaywallLayout`
(`layout:`) and `KikiPaywallPlanLayout`.

### Added

Source compatibility: `KikiAccessPaywallSheet.init` and `KikiAccessPaywallCopy.init`
keep their released signatures as overloads, so initializer references and
existing calls (including a trailing closure, which binds to `onFinish`) compile
unchanged. The expanded overloads add the new arguments.

- `KikiAccessPaywallSheet(hero:)`: a host view that replaces the icon header,
  drawn full-bleed and flush with the sheet's top and side edges. Its height is
  the view's own; the close button stays on top, and features, plans, actions
  and links keep their padding.
- `KikiAccessPaywallSheet(planLayout:)`: `.cards` (default) or `.rows`. Rows
  stack the plans full-width with title, detail line, price and badge, a 2-point
  tint ring on the selection and no radio circle; each row is one button with
  the selected trait.
- `KikiAccessPaywallSheet(width:)`: the sheet width; `nil` keeps
  `KikiPaywallDefaults.sheetWidth`.
- `KikiAccessPaywallOutcome` and `KikiAccessPaywallSheet(onPurchaseCompleted:)`:
  called on the main actor, at most once per presentation of the sheet, when a
  purchase (`.purchased(planID:)`) or restore (`.restored`) is verified. It runs
  before the sheet shows the success view or finishes. Until then the sheet keeps
  its purchase presentation even if the manager already reports Pro, so the host
  can run the action the user clicked first. Not called for a trial start, a
  cancel, a failure or an empty restore.
- `KikiAccessPaywallSheet(successContent:)`: with a host success view the sheet
  no longer finishes at once after a verified purchase or restore; it swaps its
  content for that view and one Done button and stays there until Done, even if
  the entitlement changes meanwhile. Done finishes as before. Without it,
  behavior is unchanged. A trial start still finishes immediately.
- One transaction per presentation: the sheet accepts a purchase, restore or
  trial only while idle, so a second action queued behind a successful one, or
  started while the success view is held, is ignored.
- `KikiAccessPaywallCopy(featuresHeading:)`: an optional small headline above
  the features list (for example "Included with Pro"). `nil`, the default,
  shows none.
- `KikiAccessPaywallSheet(ownerContent:)`: a host view shown instead of the
  default access summary when the user is Pro, above the usual Done button.
## 0.5.2 - 2026-10-26

### Changed

- The onboarding paywall makes "Start free trial" the primary action while a
  trial can still be started, with purchase and restore as secondary actions.
  Onboarding is the first look at the price, before the app has been used.
  The Settings paywall is unchanged: purchase stays primary.

## 0.5.1 - 2026-10-21

### Added

- `RevenueCatConfiguration(postHogUserID:)` (also on `standardPro` and
  `standardProFromInfoDictionary`). After configuring Purchases, the RevenueCat
  client sets it as the `$posthogUserId` attribute, so RevenueCat's PostHog
  integration sends purchase, renewal and expiration events under the host's
  analytics identity (for example `KikiAnalytics.installationID`). The
  RevenueCat app user ID and existing customers are unchanged. Commerce does not
  depend on any analytics package; nil or blank sets nothing.

## 0.5.0 - 2026-10-13

### Added

- `KikiAccessState.free`: an unpaid user in an app without a trial
  (`KikiTrialPolicy.disabled`). Such a user used to be reported as
  `.expired`, which invited "your trial has ended" copy and expiry prompts.
  The paywall shows `KikiAccessPaywallCopy.freeSubtitle` and offers purchase
  and restore; `KikiAccessPromptSchedule` never prompts it. The Debug
  `notPro` override returns `.free` under a disabled trial policy.
  `freeSubtitle` defaults to the main-bundle key "Choose a plan to unlock Pro.".
- `KikiAccessPlan.terms`: purchase terms shown as the paywall footnote while
  that plan is selected, so a subscription's renewal terms sit under the
  purchase button (App Review 3.1.2). `{price}` becomes the store price.
- Purchase placement: `KikiAccessPaywallSheet(placement:)` and
  `KikiAccessManager.purchase(planID:placement:)` pass the surface that opened
  the sheet to `CommerceClient.purchase(_:placement:)`. The RevenueCat client
  presents the package at that placement, so RevenueCat attributes the sale to
  it. Other clients get a default that ignores the placement.
- `KikiAccessPaywallSheet(note:)`: one host line under the purchase terms,
  inside the sheet, so hosts stop appending a second surface below it.
  Owners do not see it.

### Changed

- Pin Kiki_mackit 0.11.0.

### Migration from 0.4.0

Requires Kiki_mackit 0.11.0 (`KikiPaywallAccessState.free`). `KikiAccessState`
gains `.free`, the intended pre-1.0 minor break: exhaustive switches over it
need the new case. An app with `trialPolicy: .disabled` that matched
`.expired` to mean "free" should match `.free` instead; `.expired` now always
means a trial that ran out.

## 0.4.0 - 2026-10-04

### Added

- `KikiAccessPromptSchedule` and `KikiAccessPromptRules` pace automatic
  paywall presentation: one notice before a time trial ends, then at most
  `maximumExpiredPrompts` expiry prompts `expiredRepeatInterval` apart, only
  with an authoritative `ready` readiness. `.recommended` is two days of
  notice and three daily expiry prompts. Asking records nothing; hosts call
  `recordPresented` after presenting.

### Changed

- Pin Kiki_mackit 0.10.1 so onboarding and utility windows are centered on first launch.
- `KikiAccessPaywallSheet` shows an entitled user their access summary only:
  no plan cards, no feature list, and no "purchase options unavailable"
  message. Apple's guidance is to encourage a purchase only when someone does
  not already own it.
- Restore is a footer link rather than a second full-width button.

## 0.3.0 - 2026-09-08

### Changed

- Pin Kiki_mackit 0.10.0 for adaptive sheets and the refined component APIs.
- Allow caller-owned live plan presentation without changing commerce identity,
  availability or entitlement state.
- Preserve the 0.2.1 account-stat display API while keeping the current main
  branch's displayPlanIDs filtering.


### Fixed

- **The legacy paid-app lookup can no longer stall an entitlement refresh.**
  `AppTransaction.shared` runs first in `refreshEntitlement()` and reaches the
  App Store; on a copy with no receipt — a development build, a sandbox
  account, an offline Mac — it took seconds or never returned. It was the one
  unbounded await in that path, so a host sat on "checking purchases" for as
  long as StoreKit took. It is now bounded by the same timeout as the
  RevenueCat requests (`requestTimeoutNanoseconds`).

### Added

- **`KikiAccessDebugMode.expired`.** The debug panel could set a trial that
  never started (`notPro`) but not one that ran out, so any retention path
  gated on an expired trial was unreachable in development — the panel could
  not express a state the app acts on.

- **`displayPlanIDs` on `KikiAccessPaywallSheet`** filters which configured
  plans the sheet lists, in the host's order. Needed once a configuration
  carries a plan sold elsewhere — a win-back discount SKU must be purchasable
  through the manager without appearing beside the full-price card on the
  regular paywall. `nil` (the default) lists every plan, as before.

### Migration

- Existing copy error fields and the 0.2.1 sheet initializer remain available.
- Exhaustive switches over KikiAccessDebugMode must handle the new expired case.

## 0.2.1 - 2026-07-28

### Added

- **`stats:` on `KikiAccessPaywallSheet`.** `KikiPaywallPresentation` has
  carried a `stats` slot since Kiki 0.9.0, but the commerce sheet never
  filled it. Callers can now pass `[KikiAccessPaywallStat]` (value over
  caption, one line each) — intended for facts about the user's own account.
  Defaults to empty, so existing callers are unaffected. Pairs with the fix
  below: it is what an entitled user gets instead of plan cards.

### Fixed

- **Entitled users are no longer shown plan cards.** `KikiAccessPaywallSheet`
  passed `manager.availablePlans` to the sheet in every access state, so a
  customer who already owned Pro saw priced Yearly/Lifetime cards — one of
  them badged "Best Value" — directly under "Your Pro access is active."
  The action policy already collapsed to a single dismiss button in that
  state; the plan row was the missed half. `KikiAccessPaywallPlanPolicy`
  now gates it, and the sheet renders as a status view for entitled users.
  This also hides plans from subscribers who could move to a higher tier:
  the kit has no ordering over `CommercePlan` and cannot tell an upgrade
  from a second charge, so cross-tier upgrades need their own surface.

### Changed

- **Localization opt-in.** Every `String` default in the
  `KikiAccessPaywallCopy` initializer now resolves through the host app's
  main bundle via `String(localized:, bundle: .main, ...)` — 15 default
  values across `title`, subtitles, action titles, `loadingOptionsMessage`,
  `unavailableOptionsMessage`, purchase/restore/trial success and error
  messages. Callers that already override every field see no change;
  callers that relied on defaults now pick up translations from their own
  `Localizable.xcstrings`. Also fixed the source-side `Loading purchase
  options...` → `Loading purchase options…`. See `Docs/Localization.md`.

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
