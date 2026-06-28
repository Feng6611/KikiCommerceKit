import AppKit
import KikiCommerceCore
import KikiPaywall
import SwiftUI

public struct KikiProPaywallSheet: View {
    @ObservedObject private var manager: KikiProAccessManager
    private let context: KikiProPaywallPresentationContext
    private let copy: KikiProPaywallCopy
    private let links: KikiProExternalLinks
    private let tint: Color
    private let icon: NSImage?
    private let layout: KikiProPaywallLayout
    private let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlanID: String
    @State private var isLoadingOfferings = false
    @State private var isStartingTrial = false

    public init(
        manager: KikiProAccessManager,
        context: KikiProPaywallPresentationContext,
        copy: KikiProPaywallCopy = KikiProPaywallCopy(),
        links: KikiProExternalLinks = KikiProExternalLinks(),
        tint: Color = .accentColor,
        icon: NSImage? = nil,
        layout: KikiProPaywallLayout = .commandReopenDefault,
        onFinish: @escaping () -> Void = {}
    ) {
        self.manager = manager
        self.context = context
        self.copy = copy
        self.links = links
        self.tint = tint
        self.icon = icon
        self.layout = layout
        self.onFinish = onFinish
        _selectedPlanID = State(initialValue: manager.configuration.defaultPlanID)
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        sheetHeader
                            .padding(.top, 8)

                        if manager.status.isPro {
                            KikiProStatusCard(
                                status: manager.status,
                                copy: copy,
                                tint: tint
                            )
                        } else {
                            contentStack
                        }
                    }
                    .padding(.horizontal, sheetPadding)
                    .padding(.bottom, 14)
                }

                VStack(spacing: 8) {
                    if !manager.status.isPro {
                        actionStack
                    }
                    footer
                }
                .padding(.horizontal, sheetPadding)
                .padding(.bottom, 14)
            }

            if context == .settings {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
                .padding(20)
                .accessibilityLabel("Close")
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    colors: [tint.opacity(0.05), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 350
                )
            }
        }
        .task {
            guard !isLoadingOfferings else { return }
            isLoadingOfferings = true
            await manager.loadOfferings()
            syncSelectedPlan()
            isLoadingOfferings = false
        }
        .onChange(of: manager.availablePlans) { _ in
            syncSelectedPlan()
        }
        .interactiveDismissDisabled(context == .onboarding)
    }

    private var sheetSize: CGSize {
        layout.size(for: context)
    }

    private var sheetPadding: CGFloat {
        layout.padding(for: context)
    }

    private var selectedProduct: KikiProPlanProduct {
        manager.planProduct(for: selectedPlanID)
    }

    private var isBusy: Bool {
        isLoadingOfferings
            || isStartingTrial
            || manager.purchaseInProgressPlanID != nil
            || manager.isRestoringPurchases
    }

    private var canStartTrial: Bool {
        manager.status.canStartTrial
    }

    private var shouldUseTrialPrimaryAction: Bool {
        context == .onboarding && canStartTrial
    }

    private var sheetHeader: some View {
        VStack(spacing: 14) {
            Image(nsImage: icon ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)

            Text(copy.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(headerSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    private var contentStack: some View {
        VStack(spacing: 14) {
            KikiProUpgradeCard(
                status: manager.status,
                products: manager.availablePlans,
                selectedPlanID: $selectedPlanID,
                copy: copy,
                tint: tint,
                isBusy: isBusy,
                showsFeatures: context == .onboarding
            )

            messageStack
        }
    }

    @ViewBuilder
    private var messageStack: some View {
        if let paywallErrorMessage = manager.paywallErrorMessage {
            KikiPaywallMessage(paywallErrorMessage, tone: .danger)
        } else if let successMessage = manager.paywallSuccessMessage {
            KikiPaywallMessage(successMessage, tone: .success)
        } else if isLoadingOfferings {
            KikiPaywallMessage("Loading purchase options...", tone: .neutral)
        } else if case .expired = manager.status {
            KikiPaywallMessage("Trial ended. Your saved settings stay intact after upgrading.", tone: .warning)
        } else if !selectedProduct.isAvailable && !shouldUseTrialPrimaryAction {
            KikiPaywallMessage(
                "Purchase options are not available right now. You can try again later or restore an existing purchase.",
                tone: .neutral
            )
        }
    }

    private var actionStack: some View {
        VStack(spacing: 8) {
            Button {
                Task { await runPrimaryAction() }
            } label: {
                KikiPaywallActionLabel(
                    title: primaryButtonTitle,
                    isLoading: primaryIsLoading,
                    isProminent: true,
                    tint: tint
                )
            }
            .buttonStyle(.plain)
            .disabled(!primaryIsEnabled)
            .opacity(primaryIsEnabled ? 1 : 0.45)

            if context == .settings, canStartTrial {
                Button {
                    Task { await startTrial() }
                } label: {
                    KikiPaywallActionLabel(
                        title: "Start 2-Day Free Trial",
                        isLoading: isStartingTrial,
                        isProminent: false,
                        tint: tint
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(manager.isRestoringPurchases ? "Restoring..." : "Restore Purchase") {
                Task { await restorePurchases() }
            }
            .disabled(isBusy)

            if let termsURL = links.termsURL {
                KikiPaywallDotSeparator()
                Button("Terms") { openURL(termsURL) }
            }

            if let privacyURL = links.privacyURL {
                KikiPaywallDotSeparator()
                Button("Privacy") { openURL(privacyURL) }
            }

            if links.termsURL == nil, let supportURL = links.supportURL {
                KikiPaywallDotSeparator()
                Button("Support") { openURL(supportURL) }
            }
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private var headerSubtitle: String {
        switch manager.status {
        case .pro:
            return copy.proSubtitle
        case .notStarted:
            return copy.notStartedSubtitle
        case .trial(let daysRemaining, let expiresAt):
            if context == .onboarding {
                return copy.trialSubtitle
            }
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in your trial, expires \(formattedDate(expiresAt))."
        case .expired:
            return copy.expiredSubtitle
        }
    }

    private var primaryButtonTitle: String {
        if shouldUseTrialPrimaryAction {
            return "Start 2-Day Free Trial"
        }

        guard selectedProduct.isAvailable else {
            return isLoadingOfferings ? "Loading Purchase Options..." : "Currently Unavailable"
        }

        return "Unlock Forever - \(selectedProduct.displayPrice)"
    }

    private var primaryIsEnabled: Bool {
        if shouldUseTrialPrimaryAction {
            return !isBusy
        }

        return !isBusy && selectedProduct.isAvailable
    }

    private var primaryIsLoading: Bool {
        if shouldUseTrialPrimaryAction {
            return isStartingTrial
        }

        return isLoadingOfferings || manager.purchaseInProgressPlanID == selectedPlanID
    }

    private func priceSuffix(for product: KikiProPlanProduct) -> String? {
        KikiProUpgradeCard.priceSuffix(for: product)
    }

    private func syncSelectedPlan() {
        if manager.planProduct(for: selectedPlanID).isAvailable {
            return
        }

        if let firstAvailablePlan = manager.availablePlans.first(where: { $0.isAvailable }) {
            selectedPlanID = firstAvailablePlan.id
        }
    }

    private func runPrimaryAction() async {
        if shouldUseTrialPrimaryAction {
            await startTrial()
            return
        }

        await purchaseSelectedPlan()
    }

    private func purchaseSelectedPlan() async {
        guard selectedProduct.isAvailable else {
            return
        }

        do {
            try await manager.purchase(planID: selectedPlanID)
            if manager.status.isPro {
                finish()
            }
        } catch {
            // User-facing error state is owned by the manager.
        }
    }

    private func startTrial() async {
        isStartingTrial = true
        defer { isStartingTrial = false }
        await manager.startTrial()
        if manager.status.isActive {
            finish()
        }
    }

    private func restorePurchases() async {
        do {
            try await manager.restorePurchases()
            if manager.status.isPro {
                finish()
            }
        } catch {
            // User-facing error state is owned by the manager.
        }
    }

    private func finish() {
        if context == .settings {
            dismiss()
        }
        onFinish()
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

public struct KikiProUpgradeCard: View {
    private let status: KikiProAccessStatus
    private let products: [KikiProPlanProduct]
    @Binding private var selectedPlanID: String
    private let copy: KikiProPaywallCopy
    private let tint: Color
    private let isBusy: Bool
    private let showsFeatures: Bool

    public init(
        status: KikiProAccessStatus,
        products: [KikiProPlanProduct],
        selectedPlanID: Binding<String>,
        copy: KikiProPaywallCopy = KikiProPaywallCopy(),
        tint: Color = .accentColor,
        isBusy: Bool = false,
        showsFeatures: Bool = true
    ) {
        self.status = status
        self.products = products
        _selectedPlanID = selectedPlanID
        self.copy = copy
        self.tint = tint
        self.isBusy = isBusy
        self.showsFeatures = showsFeatures
    }

    public var body: some View {
        VStack(spacing: 0) {
            KikiPaywallStatusHeader(
                title: copy.proCardTitle,
                subtitle: cardSubtitle,
                systemName: isExpired ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                iconColor: isExpired ? .orange : tint,
                backgroundColor: isExpired ? Color.orange.opacity(0.14) : tint.opacity(0.14)
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isExpired ? Color.orange.opacity(0.10) : tint.opacity(0.08))

            VStack(spacing: 12) {
                if showsFeatures, !copy.features.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(copy.features, id: \.self) { feature in
                            KikiPaywallFeatureRow(icon: "checkmark.circle", text: feature, tint: tint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 9) {
                    ForEach(products) { product in
                        KikiPaywallPlanRow(
                            plan: product.kikiPaywallPlan,
                            isSelected: selectedPlanID == product.id,
                            tint: tint,
                            priceSuffix: Self.priceSuffix(for: product),
                            isDisabled: isBusy
                        ) {
                            selectedPlanID = product.id
                        }
                    }
                }
            }
            .padding(20)
        }
        .kikiPaywallCard()
    }

    static func priceSuffix(for product: KikiProPlanProduct) -> String? {
        let detail = product.billingDetail.lowercased()
        if detail.contains("year") {
            return "year"
        }
        if detail.contains("once") || detail.contains("one-time") {
            return "once"
        }
        return nil
    }

    private var isExpired: Bool {
        if case .expired = status {
            return true
        }
        return false
    }

    private var cardSubtitle: String {
        switch status {
        case .notStarted:
            return copy.notStartedSubtitle
        case .trial(let daysRemaining, _):
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in your Pro trial."
        case .expired:
            return copy.expiredSubtitle
        case .pro:
            return copy.proCardSubtitle
        }
    }
}

public struct KikiProStatusCard: View {
    private let status: KikiProAccessStatus
    private let copy: KikiProPaywallCopy
    private let tint: Color

    public init(
        status: KikiProAccessStatus,
        copy: KikiProPaywallCopy = KikiProPaywallCopy(),
        tint: Color = .accentColor
    ) {
        self.status = status
        self.copy = copy
        self.tint = tint
    }

    public var body: some View {
        if case .pro(let plan, let entitlement) = status {
            VStack(spacing: 0) {
                KikiPaywallStatusHeader(
                    title: copy.proCardTitle,
                    subtitle: copy.proCardSubtitle,
                    systemName: "checkmark.seal.fill",
                    iconColor: tint,
                    backgroundColor: tint.opacity(0.14)
                ) {
                    KikiPaywallPill(text: plan.title, tint: tint)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.08))

                let rows = metadataRows(entitlement: entitlement)
                if !rows.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            metadataRow(label: row.label, value: row.value)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .kikiPaywallCard()
        }
    }

    private func metadataRows(entitlement: CommerceEntitlement) -> [MetadataRow] {
        var rows: [MetadataRow] = []

        if let purchaseDate = entitlement.originalPurchaseDate {
            rows.append(MetadataRow(label: "Member since", value: formattedDate(purchaseDate)))
        }

        if let renewalState = status.renewalState {
            switch renewalState {
            case .renews(let date, _, _):
                rows.append(MetadataRow(label: "Renews", value: formattedDate(date)))
            case .ends(let date, _, _):
                rows.append(MetadataRow(label: "Ends", value: formattedDate(date)))
            }
        }

        return rows
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)

            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private struct MetadataRow: Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }
}

private extension KikiProPlanProduct {
    var kikiPaywallPlan: KikiPaywallPlan {
        KikiPaywallPlan(
            id: id,
            title: title,
            displayPrice: displayPrice,
            billingDetail: billingDetail,
            badge: badge,
            isAvailable: isAvailable
        )
    }
}
