import AppKit
import Foundation
import KikiCommerceCore
import KikiPaywall
@testable import KikiCommercePresentation
import SwiftUI
import Testing

@MainActor
struct KikiProPaywallViewsTests {
    @Test("Sheet is constructible in both contexts")
    func sheetIsConstructibleInBothContexts() {
        let manager = makeManager()

        _ = KikiAccessPaywallSheet(manager: manager, context: .settings)
        _ = KikiAccessPaywallSheet(manager: manager, context: .onboarding)
    }

    @Test("Display plan filter keeps the host's subset, in the host's order")
    func displayPlanFilter() {
        let manager = makeManager()
        let available = manager.availablePlans
        #expect(available.count == 2)

        // A win-back SKU lives in the configuration so purchase(planID:) can
        // sell it, but the regular paywall must not list it beside the full
        // price. The filter is how a host keeps such a plan out of the sheet.
        let subset = KikiAccessPaywallSheet.displayedPlans(
            from: available,
            displayPlanIDs: ["supporterLifetime"]
        )
        #expect(subset.map(\.id) == ["supporterLifetime"])

        let reordered = KikiAccessPaywallSheet.displayedPlans(
            from: available,
            displayPlanIDs: ["supporterLifetime", "lifetime"]
        )
        #expect(reordered.map(\.id) == ["supporterLifetime", "lifetime"])

        let unknown = KikiAccessPaywallSheet.displayedPlans(
            from: available,
            displayPlanIDs: ["missing"]
        )
        #expect(unknown.isEmpty)

        let all = KikiAccessPaywallSheet.displayedPlans(from: available, displayPlanIDs: nil)
        #expect(all.map(\.id) == available.map(\.id))
    }

    @Test("Footnote carries the selected plan's terms only")
    func footnoteFollowsSelection() {
        func product(_ id: String, terms: String?) -> KikiAccessPlanProduct {
            KikiAccessPlanProduct(
                plan: KikiAccessPlan(id: id, commercePlan: CommercePlan(id), title: id, fallbackDisplayPrice: "$1",
                                     billingDetail: "", subtitle: "", terms: terms),
                displayPrice: "$5", billingDetail: "", isAvailable: true)
        }
        let plans = [product("yearly", terms: "Renews at {price} a year."), product("lifetime", terms: nil),
                     product("empty", terms: "")]

        #expect(KikiAccessPaywallSheet.footnote(plans: plans, selectedPlanID: "yearly") == "Renews at $5 a year.")
        #expect(KikiAccessPaywallSheet.footnote(plans: plans, selectedPlanID: "lifetime") == nil)
        #expect(KikiAccessPaywallSheet.footnote(plans: plans, selectedPlanID: "empty") == nil)
        #expect(KikiAccessPaywallSheet.footnote(plans: [], selectedPlanID: "yearly") == nil)
        #expect(KikiAccessPaywallSheet.footnote(plans: plans, selectedPlanID: "yearly", note: "Free stays free.")
                == "Renews at $5 a year.\nFree stays free.")
        #expect(KikiAccessPaywallSheet.footnote(plans: plans, selectedPlanID: "lifetime", note: "Free stays free.")
                == "Free stays free.")
        #expect(KikiAccessPaywallSheet.footnote(plans: plans, selectedPlanID: "lifetime", note: "") == nil)
    }

    @Test("Settings keeps purchase primary and exposes trial plus restore")
    func settingsActionPolicy() {
        let policy = KikiAccessPaywallActionPolicy.resolve(
            status: .notStarted,
            context: .settings
        )

        #expect(policy.primary == .purchase)
        #expect(policy.secondary == [.startTrial, .restore])
    }

    @Test("The free tier offers purchase and restore, no trial")
    func freeTierOffersPurchaseAndRestore() {
        let policy = KikiAccessPaywallActionPolicy.resolve(
            status: .free,
            context: .settings
        )

        #expect(policy.primary == .purchase)
        #expect(policy.secondary == [.restore])
    }

    @Test("Onboarding offers purchase primary with trial and restore secondary")
    func onboardingActionPolicy() {
        let policy = KikiAccessPaywallActionPolicy.resolve(
            status: .notStarted,
            context: .onboarding
        )

        #expect(policy.primary == .purchase)
        #expect(policy.secondary == [.startTrial, .restore])
    }

    @Test("Entitled state dismisses without transaction actions")
    func entitledActionPolicy() {
        let manager = makeManager()
        let plan = manager.configuration.plans[0]
        let status = KikiAccessState.pro(
            plan: plan,
            entitlement: CommerceEntitlement(
                plan: plan.commercePlan,
                productIdentifier: "dev.kkuk.test.pro.lifetime",
                entitlementIdentifier: "pro",
                expirationDate: nil
            )
        )

        let policy = KikiAccessPaywallActionPolicy.resolve(
            status: status,
            context: .settings
        )

        #expect(policy.primary == .dismiss)
        #expect(policy.secondary.isEmpty)
    }

    @Test("Entitled users see an access summary, not the plan catalog")
    func entitledHidesCatalog() {
        let manager = makeManager()
        let plan = manager.configuration.plans[0]
        let owned = KikiAccessState.pro(
            plan: plan,
            entitlement: CommerceEntitlement(
                plan: plan.commercePlan,
                productIdentifier: "dev.kkuk.test.pro.lifetime",
                entitlementIdentifier: "pro",
                expirationDate: nil
            )
        )

        #expect(KikiAccessPaywallSheet.showsCatalog(for: owned) == false)
        #expect(KikiAccessPaywallSheet.showsCatalog(for: .expired))
        #expect(KikiAccessPaywallSheet.showsCatalog(for: .notStarted))
    }

    @Test("Workflow loads offerings before presentation")
    func workflowLoadsOfferings() async {
        let client = NoopCommerceClient()
        client.offering = CommerceOffering(
            identifier: "current",
            products: [
                CommerceProduct(
                    plan: .yearly,
                    productIdentifier: "dev.kkuk.test.pro.yearly",
                    displayPrice: "$6.99",
                    isAvailable: true
                )
            ]
        )
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)

        await workflow.loadOfferings()

        #expect(client.loadOfferingCallCount == 1)
        #expect(manager.availablePlans.first?.displayPrice == "$6.99")
    }

    @Test("Workflow reports completion only after successful access changes")
    func workflowReportsSuccessfulCompletion() async {
        let client = NoopCommerceClient()
        client.purchaseEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "dev.kkuk.test.pro.lifetime",
            entitlementIdentifier: "pro",
            expirationDate: nil
        )
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)

        let didComplete = await workflow.purchase(planID: "supporterLifetime")
        #expect(workflow.lastAction == .purchase)

        #expect(didComplete)
        #expect(manager.status.isPro)
    }

    @Test("Workflow reports completion after restore unlocks access")
    func workflowReportsRestoreCompletion() async {
        let client = NoopCommerceClient()
        client.restoreEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "dev.kkuk.test.pro.lifetime",
            entitlementIdentifier: "pro",
            expirationDate: nil
        )
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)

        let didComplete = await workflow.restorePurchases()
        #expect(workflow.lastAction == .restore)

        #expect(didComplete)
        #expect(manager.status.isPro)
    }

    @Test("Workflow reports completion after trial starts")
    func workflowReportsTrialCompletion() async {
        let manager = makeManager()
        let workflow = KikiAccessPaywallWorkflow(manager: manager)

        let didComplete = await workflow.startTrial()
        #expect(workflow.lastAction == .startTrial)

        #expect(didComplete)
        #expect(manager.status.isActive)
    }

    @Test("Workflow keeps purchase failures visible")
    func workflowKeepsPurchaseFailuresVisible() async {
        let client = NoopCommerceClient()
        client.purchaseError = CommercePurchaseError.network
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)

        let didComplete = await workflow.purchase(planID: "supporterLifetime")

        #expect(didComplete == false)
        #expect(manager.commerceFeedback == .error(.network))
    }

    @Test("Sheet accepts hero, rows, width, owner and success content")
    func sheetAcceptsHostLayout() {
        let manager = makeManager()

        _ = KikiAccessPaywallSheet(
            manager: manager,
            context: .settings,
            displayPlanIDs: nil,
            hero: AnyView(Color.orange.frame(height: 120)),
            planLayout: .rows,
            width: 440,
            ownerContent: AnyView(Text("Thank you")),
            successContent: AnyView(Text("You are in")),
            onFinish: {},
            onPurchaseCompleted: { _ in }
        )
    }

    @Test("Hero and owner content are laid out full-bleed in the sheet")
    func hostContentIsFullBleed() async {
        final class Frames {
            var hero = CGRect.zero
            var owner = CGRect.zero
            var sheet = CGRect.zero
        }
        func probe(_ keyPath: ReferenceWritableKeyPath<Frames, CGRect>, _ frames: Frames, height: CGFloat) -> AnyView {
            AnyView(Color.orange.frame(height: height).background(GeometryReader { proxy in
                Color.clear.onAppear { frames[keyPath: keyPath] = proxy.frame(in: .global) }
            }))
        }

        // A hero for a user who has not bought yet.
        let frames = Frames()
        let heroHost = NSHostingView(rootView: KikiAccessPaywallSheet(
            manager: makeManager(), context: .settings, displayPlanIDs: nil,
            hero: probe(\.hero, frames, height: 150), planLayout: .rows
        ))
        heroHost.frame = CGRect(x: 0, y: 0, width: 700, height: 900)
        await settle(heroHost)
        #expect(abs(frames.hero.width - 500) < 1)
        #expect(abs(frames.hero.height - 150) < 1)
        let heroSheetLeft = (700 - 500) / 2.0
        #expect(abs(frames.hero.minX - heroSheetLeft) < 1)

        // An owner sees the host's owner view, full width, with a custom width.
        let owner = Frames()
        let ownerClient = NoopCommerceClient()
        ownerClient.cachedEntitlement = lifetimeEntitlement
        let ownerManager = makeManager(client: ownerClient)
        #expect(ownerManager.status.isPro)
        let ownerHost = NSHostingView(rootView: KikiAccessPaywallSheet(
            manager: ownerManager, context: .settings, displayPlanIDs: nil,
            width: 420, ownerContent: probe(\.owner, owner, height: 80)
        ))
        ownerHost.frame = CGRect(x: 0, y: 0, width: 700, height: 900)
        await settle(ownerHost)
        #expect(abs(owner.owner.width - 420) < 1)
        #expect(abs(owner.owner.height - 80) < 1)
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async {
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A verified purchase reports once, then finishes at once by default")
    func purchaseCompletionFinishesByDefault() async {
        let manager = makeManager(client: purchasingClient())
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var events: [String] = []
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { events.append("completed \($0)") },
            showsSuccessContent: false,
            finish: { events.append("finish") }
        )

        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)

        #expect(events == ["completed purchased(planID: \"supporterLifetime\")", "finish"])
        #expect(workflow.successOutcome == nil)
        #expect(manager.status.isPro)
    }

    @Test("With a success view the sheet holds instead of finishing")
    func purchaseCompletionHoldsForSuccessContent() async {
        let manager = makeManager(client: purchasingClient())
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completed: [KikiAccessPaywallOutcome] = []
        var finishCount = 0
        var heldWhenReported: KikiAccessPaywallOutcome?
        var finishedWhenReported = 0
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: {
                completed.append($0)
                // The host acts before the sheet changes anything.
                heldWhenReported = workflow.successOutcome
                finishedWhenReported = finishCount
            },
            showsSuccessContent: true,
            finish: { finishCount += 1 }
        )

        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)

        #expect(completed == [.purchased(planID: "supporterLifetime")])
        #expect(heldWhenReported == nil)
        #expect(finishedWhenReported == 0)
        #expect(workflow.successOutcome == .purchased(planID: "supporterLifetime"))
        #expect(finishCount == 0)
    }

    @Test("A verified restore reports a restore outcome")
    func restoreCompletionReportsRestore() async {
        let client = NoopCommerceClient()
        client.restoreEntitlement = lifetimeEntitlement
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completed: [KikiAccessPaywallOutcome] = []
        var finishCount = 0
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { completed.append($0) },
            showsSuccessContent: false,
            finish: { finishCount += 1 }
        )

        await workflow.restoreAndComplete(completion: completion)

        #expect(completed == [.restored])
        #expect(finishCount == 1)
    }

    @Test("A failed purchase or empty restore reports nothing and keeps the sheet open")
    func failuresDoNotComplete() async {
        let client = NoopCommerceClient()
        client.purchaseError = CommercePurchaseError.network
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completedCount = 0
        var finishCount = 0
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { _ in completedCount += 1 },
            showsSuccessContent: true,
            finish: { finishCount += 1 }
        )

        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)
        await workflow.restoreAndComplete(completion: completion)

        #expect(completedCount == 0)
        #expect(finishCount == 0)
        #expect(workflow.successOutcome == nil)
    }

    @Test("Initializers keep their released function types")
    func initializerReferencesKeepTheirTypes() {
        typealias Action = () -> Void
        let sheet: (KikiAccessManager, KikiAccessPaywallContext, KikiAccessPaywallCopy, [KikiAccessPaywallStat],
                    [KikiAccessPaywallLink], [String]?, (@MainActor (KikiAccessPlanProduct) -> KikiPaywallPlanPresentation)?,
                    String?, String?, Color, @escaping Action) -> KikiAccessPaywallSheet = KikiAccessPaywallSheet.init
        let compat: (KikiAccessManager, KikiAccessPaywallContext, KikiAccessPaywallCopy, [KikiAccessPaywallStat],
                     [KikiAccessPaywallLink], Color, @escaping (KikiAccessPlanProduct) -> KikiPaywallPlanPresentation,
                     @escaping Action) -> KikiAccessPaywallSheet = KikiAccessPaywallSheet.init
        let copy: (String, String, String, String, String, String, [String], String, String, String, String, String,
                   String, String, String, String, String, String, String) -> KikiAccessPaywallCopy =
            KikiAccessPaywallCopy.init

        _ = (sheet, compat, copy)
    }

    @Test("Old-shaped calls are unambiguous and a trailing closure still binds to onFinish")
    func oldCallShapesStillCompile() {
        let manager = makeManager()
        var finished = 0

        // No new argument: resolves to the released overload.
        _ = KikiAccessPaywallSheet(manager: manager, context: .settings, displayPlanIDs: nil,
                                   placement: "settings", note: "Free stays free.", onFinish: {})
        // A zero-argument trailing closure compiles only if it binds to onFinish;
        // onPurchaseCompleted takes an outcome.
        _ = KikiAccessPaywallSheet(manager: manager, context: .settings, displayPlanIDs: nil) { finished += 1 }
        _ = KikiAccessPaywallSheet(manager: manager, context: .onboarding) { finished += 1 }
        _ = KikiAccessPaywallCopy(title: "T", features: ["A"])
        #expect(finished == 0)
    }

    @Test("The features heading is opt-in")
    func featuresHeadingDefaultsToNone() {
        #expect(KikiAccessPaywallCopy().featuresHeading == nil)
        #expect(KikiAccessPaywallCopy(features: ["A"]).featuresHeading == nil)
        #expect(KikiAccessPaywallCopy(features: ["A"], featuresHeading: "Included").featuresHeading == "Included")
    }

    @Test("A queued second action is rejected while the first executes")
    func queuedActionsAreRejected() async {
        let client = GatedCommerceClient(entitlement: lifetimeEntitlement)
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completed: [KikiAccessPaywallOutcome] = []
        var finishCount = 0
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { completed.append($0) },
            showsSuccessContent: false,
            finish: { finishCount += 1 }
        )

        let first = Task { await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion) }
        while client.purchaseCallCount == 0 { await Task.yield() }
        #expect(workflow.phase == .executing)
        let second = Task { await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion) }
        let third = Task { await workflow.restoreAndComplete(completion: completion) }
        for _ in 0..<5 { await Task.yield() }
        client.releaseAll()
        await first.value
        await second.value
        await third.value

        #expect(completed == [.purchased(planID: "supporterLifetime")])
        #expect(finishCount == 1)
        #expect(client.purchaseCallCount == 1)
        #expect(client.restoreCallCount == 0)
        #expect(workflow.phase == .finished(held: nil))
    }

    @Test("After a success, a restore or a repeated purchase does nothing")
    func nothingStartsAfterSuccess() async {
        let client = NoopCommerceClient()
        client.purchaseEntitlement = lifetimeEntitlement
        client.restoreEntitlement = lifetimeEntitlement
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completed: [KikiAccessPaywallOutcome] = []
        var finishCount = 0
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { completed.append($0) },
            showsSuccessContent: true,
            finish: { finishCount += 1 }
        )

        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)
        // Holding the success view does not unlock the workflow.
        await workflow.restoreAndComplete(completion: completion)
        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)
        await workflow.startTrialAndFinish(finish: { finishCount += 100 })

        #expect(completed == [.purchased(planID: "supporterLifetime")])
        #expect(finishCount == 0)
        #expect(workflow.phase == .holding(.purchased(planID: "supporterLifetime")))

        workflow.finishHeld(finish: { finishCount += 1 })
        workflow.finishHeld(finish: { finishCount += 1 })
        #expect(finishCount == 1)
        #expect(workflow.phase == .finished(held: .purchased(planID: "supporterLifetime")))
        // The success view stays after Done instead of flipping to the owner summary.
        #expect(workflow.mode == .success)

        await workflow.restoreAndComplete(completion: completion)
        #expect(completed.count == 1)
    }

    @Test("A callback that re-enters the workflow cannot deliver twice")
    func reentrantCallbackIsRejected() async {
        let client = NoopCommerceClient()
        client.purchaseEntitlement = lifetimeEntitlement
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completed = 0
        var nested: Task<Void, Never>?
        var completion = KikiAccessPaywallCompletion(onPurchaseCompleted: nil, showsSuccessContent: false, finish: {})
        completion.onPurchaseCompleted = { _ in
            completed += 1
            nested = Task { await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion) }
        }

        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)
        await nested?.value

        #expect(completed == 1)
    }

    @Test("Pro published mid-transaction does not change the sheet before the host is told")
    func presentationWaitsForTheCallback() async {
        let client = GatedCommerceClient(entitlement: lifetimeEntitlement)
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var modeAtCallback: KikiAccessPaywallMode?
        var statusWasProAtCallback: Bool?
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { _ in
                modeAtCallback = workflow.mode
                statusWasProAtCallback = workflow.presentedStatus.isPro
            },
            showsSuccessContent: true,
            finish: {}
        )

        let task = Task { await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion) }
        while client.purchaseCallCount == 0 { await Task.yield() }

        // The store call is still suspended, but the manager already publishes Pro.
        #expect(manager.status.isPro)
        #expect(workflow.presentedStatus.isPro == false)
        #expect(workflow.mode == .purchase)
        let policy = KikiAccessPaywallActionPolicy.resolve(status: workflow.presentedStatus, context: .settings)
        #expect(policy.primary == .purchase)
        #expect(workflow.isBusy)

        client.releaseAll()
        await task.value

        // Still the purchase presentation when the host is told; success afterwards.
        #expect(modeAtCallback == .purchase)
        #expect(statusWasProAtCallback == false)
        #expect(workflow.mode == .success)
    }

    @Test("A failure after Pro was published returns to the live presentation")
    func failureReleasesTheFrozenStatus() async {
        let client = GatedCommerceClient(entitlement: lifetimeEntitlement)
        client.failure = CommercePurchaseError.network
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        var completedCount = 0
        let completion = KikiAccessPaywallCompletion(
            onPurchaseCompleted: { _ in completedCount += 1 }, showsSuccessContent: false, finish: {})

        let task = Task { await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion) }
        while client.purchaseCallCount == 0 { await Task.yield() }
        client.releaseAll()
        await task.value

        #expect(completedCount == 0)
        #expect(workflow.phase == .idle)
        #expect(workflow.presentedStatus == manager.status)
    }

    @Test("A held success view keeps Done alone when the entitlement changes")
    func heldSuccessIgnoresEntitlementChanges() async {
        let client = NoopCommerceClient()
        client.purchaseEntitlement = lifetimeEntitlement
        let manager = makeManager(client: client)
        let workflow = KikiAccessPaywallWorkflow(manager: manager)
        let completion = KikiAccessPaywallCompletion(onPurchaseCompleted: nil, showsSuccessContent: true, finish: {})

        await workflow.purchaseAndComplete(planID: "supporterLifetime", completion: completion)
        #expect(workflow.mode == .success)

        // The entitlement lapses (or a refresh reports none) while the success view is up.
        client.entitlementDidChange?(nil)
        #expect(manager.status.isPro == false)
        #expect(workflow.mode == .success)
        let held = KikiAccessPaywallActionPolicy.resolve(
            status: manager.status, context: .settings, holdingSuccess: workflow.successOutcome != nil)
        #expect(held.primary == .dismiss)
        #expect(held.secondary.isEmpty)
        // Without the hold the same status would bring Purchase and Restore back.
        let live = KikiAccessPaywallActionPolicy.resolve(status: manager.status, context: .settings)
        #expect(live.primary == .purchase)
    }

    @Test("Paywall error copy is supplied by the host")
    func paywallErrorCopyIsHostOwned() {
        let copy = KikiAccessPaywallCopy(
            purchaseErrorMessage: "Please check your connection and try again."
        )

        #expect(copy.purchaseErrorMessage == "Please check your connection and try again.")
    }

    private var lifetimeEntitlement: CommerceEntitlement {
        CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "dev.kkuk.test.pro.lifetime",
            entitlementIdentifier: "pro",
            expirationDate: nil
        )
    }

    private func purchasingClient() -> NoopCommerceClient {
        let client = NoopCommerceClient()
        client.purchaseEntitlement = lifetimeEntitlement
        return client
    }

    private func makeManager(client: (any CommerceClient)? = nil) -> KikiAccessManager {
        let suiteName = "KikiCommercePresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let configuration = KikiAccessConfiguration(
            plans: [
                KikiAccessPlan(
                    id: "lifetime",
                    commercePlan: .yearly,
                    title: "Lifetime",
                    fallbackDisplayPrice: "$5.99",
                    billingDetail: "one-time purchase",
                    subtitle: "Unlock all features"
                ),
                KikiAccessPlan(
                    id: "supporterLifetime",
                    commercePlan: .lifetime,
                    title: "Supporter Lifetime",
                    fallbackDisplayPrice: "$10.99",
                    billingDetail: "one-time purchase",
                    subtitle: "Support development",
                    badge: "Recommended"
                )
            ],
            defaultPlanID: "supporterLifetime",
            commerceConfiguration: CommerceConfiguration(
                entitlementIdentifier: "pro",
                productIdentifiers: [
                    .yearly: "dev.kkuk.test.pro.yearly",
                    .lifetime: "dev.kkuk.test.pro.lifetime"
                ]
            ),
            trialPolicy: .explicitStart(duration: 2 * 24 * 60 * 60),
            storageKeys: .prefixed("KikiCommercePresentationTests.Pro")
        )

        return KikiAccessManager(
            configuration: configuration,
            defaults: defaults,
            commerceClient: client ?? NoopCommerceClient(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }
}

/// A client whose purchase publishes the entitlement, then suspends until released,
/// the way a store call can: the manager sees Pro before `purchase` returns.
@MainActor
private final class GatedCommerceClient: CommerceClient {
    var cachedEntitlement: CommerceEntitlement?
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)?
    var failure: Error?
    private let entitlement: CommerceEntitlement
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var purchaseCallCount = 0
    private(set) var restoreCallCount = 0

    init(entitlement: CommerceEntitlement) {
        self.entitlement = entitlement
    }

    func releaseAll() {
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume() }
    }

    func configureIfNeeded() {}
    func refreshEntitlement() async throws -> CommerceEntitlement? { cachedEntitlement }
    func loadOffering() async throws -> CommerceOffering? { nil }

    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        purchaseCallCount += 1
        cachedEntitlement = entitlement
        entitlementDidChange?(entitlement)
        await withCheckedContinuation { waiting.append($0) }
        if let failure { throw failure }
        return entitlement
    }

    func restorePurchases() async throws -> CommerceEntitlement? {
        restoreCallCount += 1
        await withCheckedContinuation { waiting.append($0) }
        return entitlement
    }
}

@MainActor
private final class NoopCommerceClient: CommerceClient {
    var cachedEntitlement: CommerceEntitlement?
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)?
    var offering: CommerceOffering?
    var purchaseEntitlement: CommerceEntitlement?
    var restoreEntitlement: CommerceEntitlement?
    var purchaseError: Error?
    var loadOfferingCallCount = 0

    func configureIfNeeded() {}
    func refreshEntitlement() async throws -> CommerceEntitlement? { nil }
    func loadOffering() async throws -> CommerceOffering? {
        loadOfferingCallCount += 1
        return offering
    }
    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        if let purchaseError {
            throw purchaseError
        }
        return purchaseEntitlement
    }
    func restorePurchases() async throws -> CommerceEntitlement? { restoreEntitlement }
}
