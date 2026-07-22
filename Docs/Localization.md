# KikiCommerceKit Localization

KikiCommerceKit follows the same rule as
[Kiki_mackit/Docs/Localization.md](../../Kiki_mackit/Docs/Localization.md):
the package does not ship its own catalog. Every user-facing string is
caller-owned, and any string synthesized inside the library resolves against
the host application's main bundle.

Because Commerce owns paywall, purchase, trial, and restore flows, its
strings are more sensitive than base-kit UI: getting a subscription price,
trial-end date, or restore-purchase button wrong is a purchase-safety issue,
not just a polish issue. The three shapes below are the same as Kiki, but
Commerce should default to shape 1 (caller-provided) even more aggressively.

## Rule

1. **Caller passes localized strings in.** The primary contract is via copy
   structs the caller populates, e.g. `KikiAccessPaywallCopy`,
   `KikiProPaywallCopy`, `KikiAccessStatusPresentation`. Every field is
   caller-owned. Product-facing strings (plan titles, subtitles, feature
   bullets, expired-trial message) belong to the app, not the SDK, because
   the app knows the product name, tone, and channel.

2. **Kit-owned defaults resolve from the caller's main bundle.** When a
   copy struct provides a `String = "..."` default so the caller can adopt
   without wiring every field, the default MUST be
   `String(localized: "...", bundle: .main)` — otherwise the plain English
   default silently overrides any translation the caller placed in their
   `Localizable.xcstrings` under the same source key. Default and override
   must both localize.

3. **Package-owned catalog** is currently absent and should stay absent.
   Every string a paywall or purchase flow shows can, and should, come from
   the app.

Never render a raw provider error string to the user. `RevenueCatError`,
`StoreKitError`, and their descriptions are diagnostic; wrap them in a
caller-provided message. Log the raw code separately for support triage.

Never assemble a price + period at runtime by concatenation
(`price + " / " + period`). Use a localized template such as
`String(localized: "\(price) per year")` and let the catalog control word
order, spacing, and currency-adjacent glyphs per locale.

## Caller responsibility

For every default value in a Kit copy struct, the adopting app is expected
to either:

- override the field with `String(localized: "…")` at construction, or
- add the exact default source string as a key in the app's
  `Localizable.xcstrings` and translate it per locale.

If the app does neither, the paywall renders in English regardless of
system language — this is the failure mode Command Reopen was previously
shipping under.

## Current status (2026-07-21)

Zero `String(localized:)` calls in the package. `KikiProPaywallCopy`
initializer defaults are all plain Swift literals; overriding at the call
site works, but relying on defaults ships English to every locale.

### KikiProPaywallCopy defaults to convert to `bundle: .main`

`KikiCommerceKit/Sources/KikiCommercePresentation/KikiProPaywallCopy.swift`:

| Line | Field | Current default |
|---:|---|---|
| 24 | `title` | `"Choose your plan"` |
| 25 | `proSubtitle` | `"All features are unlocked."` |
| 26 | `trialSubtitle` | `"Choose a plan or continue with your trial."` |
| 27 | `expiredSubtitle` | `"Your trial has ended. Upgrade to keep using Pro."` |
| 28 | `notStartedSubtitle` | `"Choose a plan or start your free trial."` |
| 30 | `purchaseActionTitle` | `"Unlock forever"` |
| 31 | `trialActionTitle` | `"Start free trial"` |
| 32 | `restoreActionTitle` | `"Restore purchases"` |
| 34 | `loadingOptionsMessage` | `"Loading purchase options..."` (fix `...` → `…`) |
| 35 | `unavailableOptionsMessage` | `"Purchase options are unavailable right now. Try again later or restore an existing purchase."` |
| 36 | `purchaseSuccessMessage` | `"Purchase successful. Pro unlocked."` |
| 37 | `restoreSuccessMessage` | `"Purchase restored."` |
| 38 | `noActivePurchaseMessage` | `"No active purchase found on this account."` |

Suggested change shape (illustrative — apply on next Kit release):

```swift
public init(
    title: String = String(
        localized: "Choose your plan",
        bundle: .main,
        comment: "Paywall header when the user has not chosen a plan yet."
    ),
    proSubtitle: String = String(
        localized: "All features are unlocked.",
        bundle: .main,
        comment: "Paywall subtitle when the user already owns Pro."
    ),
    // …
)
```

### Purchase error strings

`KikiCommerceKit/Sources/KikiCommerceCore/CommercePurchaseError.swift`
returns English descriptions from `errorDescription`. These are surfaced to
the user via `KikiAccessManager.readiness` and the paywall action pipeline.
They should either:

- be wrapped in `String(localized:, bundle: .main)` inside the switch, or
- be replaced with a semantic enum the caller translates.

Prefer the second option for anything the user sees. The raw description
still has value for logs; expose it separately as `debugDescription`.

### Debug labels

`KikiCommerceCore/KikiProModels.swift:163,165` returns `"Not Pro"` /
`"Pro"` as tier debug labels. These are not user-facing today; keep as
plain English until a UI surface actually consumes them.

## Testing

Test transitions between paywall states, not the exact English string a
default resolves to. Any assertion that reads
`copy.trialActionTitle == "Start free trial"` becomes fragile once the
default flows through `bundle: .main` and picks up a localized value in the
test host.
