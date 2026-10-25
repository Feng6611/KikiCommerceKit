import Combine
import KikiCommerceCore
import KikiPaywall
import SwiftUI

enum KikiAccessPaywallActionKind: Equatable {
    case purchase
    case startTrial
    case restore
    case dismiss
}

struct KikiAccessPaywallActionPolicy: Equatable {
    let primary: KikiAccessPaywallActionKind
    let secondary: [KikiAccessPaywallActionKind]

    /// - Parameter holdingSuccess: the sheet is held on the host's success view.
    ///   It offers Done alone, whatever the live entitlement does meanwhile.
    static func resolve(
        status: KikiAccessState,
        context: KikiAccessPaywallContext,
        holdingSuccess: Bool = false
    ) -> Self {
        if holdingSuccess || status.isPro {
            return Self(primary: .dismiss, secondary: [])
        }

        if status.canStartTrial {
            // Onboarding is the first look at the price, before the app has
            // been used: starting the trial is the way forward, and buying
            // stays one tap away. Settings is a deliberate visit to buy.
            if context == .onboarding {
                return Self(primary: .startTrial, secondary: [.purchase, .restore])
            }
            return Self(primary: .purchase, secondary: [.startTrial, .restore])
        }

        return Self(primary: .purchase, secondary: [.restore])
    }
}

/// How a verified transaction ended, reported to `onPurchaseCompleted`.
public enum KikiAccessPaywallOutcome: Equatable, Sendable {
    /// The user bought `planID` and access is verified.
    case purchased(planID: String)
    /// A restore found an active purchase and access is verified.
    case restored
}

/// What the sheet does once a purchase or restore is verified.
struct KikiAccessPaywallCompletion {
    var onPurchaseCompleted: (@MainActor (KikiAccessPaywallOutcome) -> Void)?
    /// Hold the sheet open on the host's success view instead of finishing.
    var showsSuccessContent: Bool
    var finish: @MainActor () -> Void
}

/// Where one presentation of the sheet is in its single transaction.
///
/// `idle -> executing -> holding -> finished` (success view), or
/// `idle -> executing -> finished` (finish at once). A failure or cancel returns
/// `executing` to `idle`. Only `idle` accepts a purchase, restore or trial, so a
/// second action queued behind a successful one is rejected, and nothing starts
/// again after success.
enum KikiAccessPaywallPhase: Equatable {
    case idle
    /// A purchase, restore or trial start was accepted and has not finished. The
    /// sheet keeps its pre-transaction presentation until the host has been told.
    case executing
    /// A verified transaction is held on the host's success view; Done finishes.
    case holding(KikiAccessPaywallOutcome)
    /// The sheet's finish path ran. `held` is the outcome shown on the success
    /// view, if any, so the view does not flip to the owner summary afterwards.
    case finished(held: KikiAccessPaywallOutcome?)
}

/// What the sheet shows, independent of the entitlement racing underneath it.
enum KikiAccessPaywallMode: Equatable {
    case purchase
    case owner
    case success
}

@MainActor
final class KikiAccessPaywallWorkflow: ObservableObject {
    @Published private(set) var isLoadingOfferings = false
    @Published private(set) var isStartingTrial = false
    @Published private(set) var lastAction: KikiAccessPaywallActionKind?
    @Published private(set) var phase: KikiAccessPaywallPhase = .idle

    /// The status when the transaction was accepted. The manager can publish Pro
    /// while the store call is still suspended; the sheet keeps showing this
    /// until the host has been told.
    private var frozenStatus: KikiAccessState?
    private var completionDelivered = false

    private let manager: KikiAccessManager

    init(manager: KikiAccessManager) {
        self.manager = manager
    }

    var isBusy: Bool {
        isTransactionBusy || phase == .executing
    }

    private var isTransactionBusy: Bool {
        isLoadingOfferings
            || isStartingTrial
            || manager.purchaseInProgressPlanID != nil
            || manager.isRestoringPurchases
    }

    /// The status the sheet should present: frozen while a transaction is
    /// executing, live otherwise.
    var presentedStatus: KikiAccessState {
        phase == .executing ? (frozenStatus ?? manager.status) : manager.status
    }

    /// The outcome the success view stands for, while held or after its Done.
    var successOutcome: KikiAccessPaywallOutcome? {
        switch phase {
        case .holding(let outcome), .finished(held: .some(let outcome)):
            return outcome
        case .idle, .executing, .finished(held: .none):
            return nil
        }
    }

    var mode: KikiAccessPaywallMode {
        if successOutcome != nil { return .success }
        return presentedStatus.isPro ? .owner : .purchase
    }

    func loadOfferings() async {
        guard !isTransactionBusy else {
            return
        }

        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        await manager.loadOfferings()
    }

    func purchase(planID: String, placement: String? = nil) async -> Bool {
        guard !isTransactionBusy else {
            return false
        }
        lastAction = .purchase

        do {
            try await manager.purchase(planID: planID, placement: placement)
            return manager.status.isPro
        } catch {
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard !isTransactionBusy else {
            return false
        }
        lastAction = .restore

        do {
            try await manager.restorePurchases()
            return manager.status.isPro
        } catch {
            return false
        }
    }

    /// Accepts the action only while idle, before any await, so a second
    /// action queued behind it is turned away rather than racing it.
    private func reserve() -> Bool {
        guard phase == .idle, !isTransactionBusy else {
            return false
        }
        frozenStatus = manager.status
        phase = .executing
        return true
    }

    private func release() {
        frozenStatus = nil
        phase = .idle
    }

    /// Purchases, and on success reports the outcome once and then either
    /// shows the success view or finishes. Ignored unless the sheet is idle.
    func purchaseAndComplete(
        planID: String,
        placement: String? = nil,
        completion: KikiAccessPaywallCompletion
    ) async {
        guard reserve() else { return }
        guard await purchase(planID: planID, placement: placement) else {
            release()
            return
        }
        complete(.purchased(planID: planID), completion)
    }

    /// Restores, and on success reports the outcome once and then either
    /// shows the success view or finishes. Ignored unless the sheet is idle.
    func restoreAndComplete(completion: KikiAccessPaywallCompletion) async {
        guard reserve() else { return }
        guard await restorePurchases() else {
            release()
            return
        }
        complete(.restored, completion)
    }

    /// Starts the trial and finishes at once. Ignored unless the sheet is idle.
    func startTrialAndFinish(finish: @MainActor () -> Void) async {
        guard reserve() else { return }
        guard await startTrial() else {
            release()
            return
        }
        frozenStatus = nil
        phase = .finished(held: nil)
        finish()
    }

    /// Done on the success view. The first call finishes; later ones do nothing.
    func finishHeld(finish: @MainActor () -> Void) {
        guard case .holding(let outcome) = phase else { return }
        phase = .finished(held: outcome)
        finish()
    }

    /// The host acts first, while the sheet still shows the purchase UI and
    /// refuses new actions, so the action the user originally clicked runs
    /// before anything changes on screen. Delivery is marked before host code
    /// runs, so a callback that re-enters cannot deliver twice.
    private func complete(_ outcome: KikiAccessPaywallOutcome, _ completion: KikiAccessPaywallCompletion) {
        guard !completionDelivered else { return }
        completionDelivered = true
        completion.onPurchaseCompleted?(outcome)
        frozenStatus = nil
        if completion.showsSuccessContent {
            phase = .holding(outcome)
        } else {
            phase = .finished(held: nil)
            completion.finish()
        }
    }

    func startTrial() async -> Bool {
        guard !isTransactionBusy else {
            return false
        }
        lastAction = .startTrial

        isStartingTrial = true
        defer { isStartingTrial = false }
        await manager.startTrial()
        return manager.status.isActive
    }
}

public struct KikiAccessPaywallSheet: View {
    @ObservedObject private var manager: KikiAccessManager
    @StateObject private var workflow: KikiAccessPaywallWorkflow
    private let context: KikiAccessPaywallContext
    private let copy: KikiAccessPaywallCopy
    private let stats: [KikiAccessPaywallStat]
    private let footerLinks: [KikiAccessPaywallLink]
    private let displayPlanIDs: [String]?
    /// Hosts can keep commerce configuration stable while resolving card copy
    /// from a live, app-owned locale at render time.
    private let planPresentation: (@MainActor (KikiAccessPlanProduct) -> KikiPaywallPlanPresentation)?
    private let placement: String?
    private let note: String?
    private let hero: AnyView?
    private let planLayout: KikiPaywallPlanLayout
    private let width: CGFloat?
    private let ownerContent: AnyView?
    private let successContent: AnyView?
    private let tint: Color
    private let onFinish: () -> Void
    private let onPurchaseCompleted: (@MainActor (KikiAccessPaywallOutcome) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String

    /// - Parameter displayPlanIDs: plans this sheet shows, in order. `nil`
    ///   shows every configured plan. Pass a subset when the configuration
    ///   carries plans that are sold elsewhere — a win-back discount SKU must
    ///   be purchasable through the manager without appearing as a third card
    ///   on the regular paywall, where it would undercut the listed price.
    /// - Parameter planPresentation: Optional host-owned display mapping for
    ///   plan cards. Use this for an in-app language switch: manager
    ///   configuration is long-lived and cannot react to a locale change.
    /// - Parameter placement: the surface that opened this sheet; a purchase
    ///   from it is attributed to that placement in the store's analytics.
    /// - Parameter note: one host line under the purchase terms, inside the
    ///   sheet (for example what stays free). Not shown to an owner.
    /// - Parameter hero: a host view that replaces the icon, title and subtitle
    ///   header. It is drawn full-bleed, flush with the sheet's top and side
    ///   edges, and decides its own height; the close button stays on top of it.
    ///   Features, plans, actions and links keep their padding. It also replaces
    ///   the default owner header, so pass `ownerContent` too if owners need words.
    /// - Parameter planLayout: `.cards` (default) lays the plans side by side;
    ///   `.rows` stacks them as full-width rows with a tint ring on the
    ///   selection.
    /// - Parameter width: the sheet width. `nil` keeps `KikiPaywallDefaults.sheetWidth`
    ///   (the onboarding size in an onboarding context).
    /// - Parameter ownerContent: a host view shown instead of the default access
    ///   summary when the user is Pro. It is drawn full-bleed above the Done
    ///   button, so the host owns its padding. `nil` keeps the default summary.
    /// - Parameter successContent: a host view for a verified purchase or
    ///   restore. When set, the sheet does not finish at once; it swaps its
    ///   content for this view and a single Done button, and stays on it until
    ///   Done (or close), whatever the entitlement does meanwhile. `nil` keeps
    ///   today's behavior: finish immediately. Starting a trial always finishes
    ///   immediately.
    /// - Parameter onPurchaseCompleted: called on the main actor, at most once
    ///   per presentation of the sheet, when a purchase or restore is verified.
    ///   It runs before the sheet shows the success view or finishes, and the
    ///   sheet keeps its purchase presentation until then (the manager may
    ///   already report Pro), so the host can run the action the user asked for
    ///   first. After a success the sheet accepts no further purchase, restore
    ///   or trial. It is not called for a trial start, a cancelled purchase or a
    ///   failure. A restore that finds nothing is not a success.
    public init(
        manager: KikiAccessManager,
        context: KikiAccessPaywallContext,
        copy: KikiAccessPaywallCopy = KikiAccessPaywallCopy(),
        stats: [KikiAccessPaywallStat] = [],
        footerLinks: [KikiAccessPaywallLink] = [],
        displayPlanIDs: [String]?,
        planPresentation: (@MainActor (KikiAccessPlanProduct) -> KikiPaywallPlanPresentation)? = nil,
        placement: String? = nil,
        note: String? = nil,
        hero: AnyView? = nil,
        planLayout: KikiPaywallPlanLayout = .cards,
        width: CGFloat? = nil,
        ownerContent: AnyView? = nil,
        successContent: AnyView? = nil,
        tint: Color = .accentColor,
        onFinish: @escaping () -> Void = {},
        onPurchaseCompleted: (@MainActor (KikiAccessPaywallOutcome) -> Void)? = nil
    ) {
        self.manager = manager
        self.context = context
        self.copy = copy
        self.stats = stats
        self.footerLinks = footerLinks
        self.displayPlanIDs = displayPlanIDs
        self.planPresentation = planPresentation
        self.placement = placement
        self.note = note
        self.hero = hero
        self.planLayout = planLayout
        self.width = width
        self.ownerContent = ownerContent
        self.successContent = successContent
        self.tint = tint
        self.onFinish = onFinish
        self.onPurchaseCompleted = onPurchaseCompleted
        _workflow = StateObject(wrappedValue: KikiAccessPaywallWorkflow(manager: manager))
        _selectedPlanID = State(initialValue: manager.configuration.defaultPlanID)
    }

    /// The 0.5.0 entry, kept with its exact signature so initializer references
    /// and existing call sites keep compiling. It shows the standard paywall.
    public init(
        manager: KikiAccessManager,
        context: KikiAccessPaywallContext,
        copy: KikiAccessPaywallCopy = KikiAccessPaywallCopy(),
        stats: [KikiAccessPaywallStat] = [],
        footerLinks: [KikiAccessPaywallLink] = [],
        displayPlanIDs: [String]?,
        planPresentation: (@MainActor (KikiAccessPlanProduct) -> KikiPaywallPlanPresentation)? = nil,
        placement: String? = nil,
        note: String? = nil,
        tint: Color = .accentColor,
        onFinish: @escaping () -> Void = {}
    ) {
        self.init(
            manager: manager,
            context: context,
            copy: copy,
            stats: stats,
            footerLinks: footerLinks,
            displayPlanIDs: displayPlanIDs,
            planPresentation: planPresentation,
            placement: placement,
            note: note,
            hero: nil,
            planLayout: .cards,
            width: nil,
            ownerContent: nil,
            successContent: nil,
            tint: tint,
            onFinish: onFinish,
            onPurchaseCompleted: nil
        )
    }

    /// Compatibility entry for 0.2.1 callers, including initializer references.
    public init(
        manager: KikiAccessManager,
        context: KikiAccessPaywallContext,
        copy: KikiAccessPaywallCopy = KikiAccessPaywallCopy(),
        stats: [KikiAccessPaywallStat] = [],
        footerLinks: [KikiAccessPaywallLink] = [],
        tint: Color = .accentColor,
        planPresentation: @escaping (KikiAccessPlanProduct) -> KikiPaywallPlanPresentation = { product in
            KikiPaywallPlanPresentation(id: product.id, title: product.title, displayPrice: product.displayPrice,
                                       billingDetail: product.billingDetail, badge: product.badge,
                                       isAvailable: product.isAvailable)
        },
        onFinish: @escaping () -> Void = {}
    ) {
        self.init(manager: manager, context: context, copy: copy, stats: stats,
                  footerLinks: footerLinks, displayPlanIDs: nil, planPresentation: planPresentation,
                  tint: tint, onFinish: onFinish)
    }

    public var body: some View {
        let presentation = makePresentation()
        let layout = makeLayout()
        return Group {
            switch context {
            case .onboarding:
                KikiOnboardingPaywall(
                    presentation: presentation,
                    selectedPlanID: $selectedPlanID,
                    tint: tint,
                    layout: layout
                )
            case .settings:
                KikiCompactPaywall(
                    presentation: presentation,
                    selectedPlanID: $selectedPlanID,
                    tint: tint,
                    showsCloseButton: true,
                    layout: layout
                )
            }
        }
        .task {
            await workflow.loadOfferings()
            syncSelectedPlan()
        }
        .onChange(of: manager.availablePlans) { _ in
            syncSelectedPlan()
        }
        .interactiveDismissDisabled(context == .onboarding)
    }

    /// The entitlement the sheet presents. It stays at the pre-transaction value
    /// while a purchase or restore is executing, because the manager may publish
    /// Pro before the store call returns and before the host has been told.
    private var status: KikiAccessState {
        workflow.presentedStatus
    }

    private var showsCatalog: Bool {
        workflow.mode == .purchase && Self.showsCatalog(for: status)
    }

    /// Which host view, if any, stands in for the sheet's content. The mode
    /// comes from the workflow, not from the live entitlement: a held success
    /// view stays until Done, and the owner view waits for the host callback.
    private func makeLayout() -> KikiPaywallLayout {
        switch workflow.mode {
        case .success:
            if let successContent {
                return KikiPaywallLayout(width: width, replacementContent: successContent)
            }
        case .owner:
            if let ownerContent {
                return KikiPaywallLayout(width: width, replacementContent: ownerContent)
            }
        case .purchase:
            break
        }
        return KikiPaywallLayout(
            hero: hero,
            planLayout: planLayout,
            width: width,
            featuresHeading: copy.featuresHeading
        )
    }

    private func makePresentation() -> KikiPaywallPresentation {
        // The success view stands alone: the feedback banner and store links
        // belong to the purchase surface it replaced.
        let isShowingSuccess = workflow.mode == .success
        return KikiPaywallPresentation(
            accessState: accessState,
            headerTitle: copy.title,
            headerSubtitle: subtitle,
            plans: plans,
            // An owner is not being sold to. Listing features and prices to
            // someone who already paid reads as "did my purchase go through?".
            features: showsCatalog ? copy.features : [],
            stats: stats.map { KikiPaywallStatConfig(id: $0.id, value: $0.value, label: $0.label) },
            footnote: Self.footnote(plans: displayedPlans, selectedPlanID: selectedPlanID,
                                    note: showsCatalog ? note : nil),
            footerLinks: isShowingSuccess ? [] : footerLinks.map {
                KikiPaywallLinkPresentation(id: $0.id, title: $0.title, url: $0.url)
            },
            message: isShowingSuccess ? nil : message,
            isInteractionDisabled: workflow.isBusy,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
            dismiss: finishFromDone
        )
    }

    private var accessState: KikiPaywallAccessState {
        if let outcome = workflow.successOutcome {
            return .entitled(planTitle: heldPlanTitle(for: outcome))
        }
        switch status {
        case .notStarted:
            return .notStarted
        case .trial:
            return .trial
        case .expired:
            return .expired
        case .free:
            return .free
        case .pro(let plan, _):
            return .entitled(planTitle: presentation(for: manager.planProduct(for: plan.id)).title)
        }
    }

    /// The plan the success view stands for, whatever the live entitlement says now.
    private func heldPlanTitle(for outcome: KikiAccessPaywallOutcome) -> String {
        switch outcome {
        case .purchased(let planID):
            return presentation(for: manager.planProduct(for: planID)).title
        case .restored:
            if case .pro(let plan, _) = manager.status {
                return presentation(for: manager.planProduct(for: plan.id)).title
            }
            return presentation(for: manager.planProduct(for: manager.configuration.defaultPlanID)).title
        }
    }

    private var subtitle: String {
        if workflow.successOutcome != nil {
            return copy.proSubtitle
        }
        switch status {
        case .notStarted:
            return copy.notStartedSubtitle
        case .trial:
            return copy.trialSubtitle
        case .expired:
            return copy.expiredSubtitle
        case .free:
            return copy.freeSubtitle
        case .pro:
            return copy.proSubtitle
        }
    }

    private var displayedPlans: [KikiAccessPlanProduct] {
        guard showsCatalog else { return [] }
        return Self.displayedPlans(from: manager.availablePlans, displayPlanIDs: displayPlanIDs)
    }

    /// Whether the sheet lists plans and features for this state. An entitled
    /// user sees their access summary — subtitle, host stats and Done — only.
    static func showsCatalog(for status: KikiAccessState) -> Bool {
        !status.isPro
    }

    /// The selected plan's purchase terms, then the host's note, under the purchase button.
    static func footnote(plans: [KikiAccessPlanProduct], selectedPlanID: String, note: String? = nil) -> String? {
        let terms = plans.first { $0.id == selectedPlanID }?.terms
        let lines = [terms, note].compactMap { $0 }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func displayedPlans(
        from availablePlans: [KikiAccessPlanProduct],
        displayPlanIDs: [String]?
    ) -> [KikiAccessPlanProduct] {
        guard let displayPlanIDs else {
            return availablePlans
        }
        return displayPlanIDs.compactMap { id in
            availablePlans.first { $0.id == id }
        }
    }

    private var plans: [KikiPaywallPlanPresentation] {
        displayedPlans.map(presentation(for:))
    }

    private func presentation(for product: KikiAccessPlanProduct) -> KikiPaywallPlanPresentation {
        planPresentation?(product) ?? KikiPaywallPlanPresentation(
            id: product.id,
            title: product.title,
            displayPrice: product.displayPrice,
            billingDetail: product.billingDetail,
            badge: product.badge,
            isAvailable: product.isAvailable
        )
    }

    private var primaryAction: KikiPaywallActionPresentation {
        actionPresentation(for: actionPolicy.primary)
    }

    private var secondaryActions: [KikiPaywallActionPresentation] {
        actionPolicy.secondary.map(actionPresentation(for:))
    }

    private var actionPolicy: KikiAccessPaywallActionPolicy {
        .resolve(status: status, context: context, holdingSuccess: workflow.successOutcome != nil)
    }

    private func actionPresentation(
        for kind: KikiAccessPaywallActionKind
    ) -> KikiPaywallActionPresentation {
        switch kind {
        case .purchase:
            return purchaseAction
        case .startTrial:
            return trialAction
        case .restore:
            return restoreAction
        case .dismiss:
            return KikiPaywallActionPresentation(
                title: copy.doneActionTitle,
                action: finishFromDone
            )
        }
    }

    private var purchaseAction: KikiPaywallActionPresentation {
        KikiPaywallActionPresentation(
            title: copy.purchaseActionTitle,
            isLoading: manager.purchaseInProgressPlanID != nil,
            isEnabled: { planID in
                manager.planProduct(for: planID).isAvailable
            },
            action: { planID in
                let completion = completion
                Task { @MainActor in
                    await workflow.purchaseAndComplete(planID: planID, placement: placement, completion: completion)
                }
            }
        )
    }

    private var trialAction: KikiPaywallActionPresentation {
        KikiPaywallActionPresentation(
            title: copy.trialActionTitle,
            isLoading: workflow.isStartingTrial,
            action: {
                let finish = finish
                Task { @MainActor in
                    await workflow.startTrialAndFinish(finish: finish)
                }
            }
        )
    }

    private var restoreAction: KikiPaywallActionPresentation {
        // A footer link, not a second full-width button: restore is required
        // to be reachable, not to compete with the purchase it sits under.
        KikiPaywallActionPresentation(
            title: copy.restoreActionTitle,
            isLoading: manager.isRestoringPurchases,
            style: .footerLink,
            action: {
                let completion = completion
                Task { @MainActor in
                    await workflow.restoreAndComplete(completion: completion)
                }
            }
        )
    }

    private var completion: KikiAccessPaywallCompletion {
        KikiAccessPaywallCompletion(
            onPurchaseCompleted: onPurchaseCompleted,
            showsSuccessContent: successContent != nil,
            finish: finish
        )
    }

    /// Done and the close button. On a held success view the first press
    /// finishes through the workflow; otherwise it is the plain finish path.
    private func finishFromDone() {
        if workflow.successOutcome != nil {
            workflow.finishHeld(finish: finish)
        } else {
            finish()
        }
    }

    private var message: KikiPaywallMessagePresentation? {
        if let feedback = manager.commerceFeedback {
            switch feedback {
            case .purchaseSucceeded:
                return KikiPaywallMessagePresentation(
                    text: copy.purchaseSuccessMessage,
                    tone: .success
                )
            case .restoreSucceeded:
                return KikiPaywallMessagePresentation(
                    text: copy.restoreSuccessMessage,
                    tone: .success
                )
            case .noActivePurchase:
                return KikiPaywallMessagePresentation(
                    text: copy.noActivePurchaseMessage,
                    tone: .warning
                )
            case .error:
                return KikiPaywallMessagePresentation(
                    text: workflow.lastAction == .restore ? copy.restoreErrorMessage
                        : workflow.lastAction == .startTrial ? copy.trialErrorMessage : copy.purchaseErrorMessage,
                    tone: .danger
                )
            }
        }
        if workflow.isLoadingOfferings {
            return KikiPaywallMessagePresentation(text: copy.loadingOptionsMessage)
        }
        if showsCatalog,
           displayedPlans.allSatisfy({ !$0.isAvailable }),
           status.canStartTrial == false {
            return KikiPaywallMessagePresentation(
                text: copy.unavailableOptionsMessage
            )
        }
        return nil
    }

    private func syncSelectedPlan() {
        let displayed = displayedPlans
        if displayed.contains(where: { $0.id == selectedPlanID && $0.isAvailable }) {
            return
        }

        if let firstAvailablePlan = displayed.first(where: \.isAvailable) {
            selectedPlanID = firstAvailablePlan.id
        }
    }

    private func finish() {
        if context == .settings {
            dismiss()
        }
        onFinish()
    }
}
