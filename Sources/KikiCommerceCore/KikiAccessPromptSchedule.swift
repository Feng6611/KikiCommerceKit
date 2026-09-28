import Foundation

/// When an app may put its paywall in front of the user without being asked.
///
/// Every paid app answers the same three questions, and each app had been
/// answering them in its own view code: warn before a time trial ends, ask
/// once it has ended, and stop asking at some point. The schedule owns only
/// that pacing. The app still decides *where* a prompt appears (Settings,
/// a sheet, after a successful product action), what it says, and which
/// product moment is appropriate.
public struct KikiAccessPromptRules: Equatable, Sendable {
    /// How long before a time trial ends the single advance notice becomes
    /// due. `nil` disables the notice.
    public var trialEndingNotice: TimeInterval?
    /// Minimum time between automatic prompts after the trial has ended.
    /// `nil` allows only one.
    public var expiredRepeatInterval: TimeInterval?
    /// Total automatic prompts after expiry. Afterwards the paywall stays
    /// reachable only from the host's own entry points.
    public var maximumExpiredPrompts: Int

    public init(
        trialEndingNotice: TimeInterval?,
        expiredRepeatInterval: TimeInterval?,
        maximumExpiredPrompts: Int
    ) {
        self.trialEndingNotice = trialEndingNotice
        self.expiredRepeatInterval = expiredRepeatInterval
        self.maximumExpiredPrompts = max(0, maximumExpiredPrompts)
    }

    /// Two days of notice, then at most three expiry prompts a day apart.
    ///
    /// Two days is the notice interval of the published transparent-trial
    /// cases: long enough to use the trial with the decision in mind. The
    /// expiry cap keeps a declined user from being asked every day forever.
    public static let recommended = KikiAccessPromptRules(
        trialEndingNotice: 2 * 24 * 60 * 60,
        expiredRepeatInterval: 24 * 60 * 60,
        maximumExpiredPrompts: 3
    )
}

public enum KikiAccessPrompt: Equatable, Sendable {
    /// A running time trial is inside its notice window.
    case trialEndingSoon(daysRemaining: Int)
    /// The trial has ended without a purchase.
    case trialEnded
}

public struct KikiAccessPromptStorageKeys: Equatable, Sendable {
    public let trialEndingNoticeShownAt: String
    public let expiredPromptDates: String

    public init(trialEndingNoticeShownAt: String, expiredPromptDates: String) {
        self.trialEndingNoticeShownAt = trialEndingNoticeShownAt
        self.expiredPromptDates = expiredPromptDates
    }

    public static func prefixed(_ prefix: String) -> Self {
        Self(
            trialEndingNoticeShownAt: "\(prefix).trialEndingNoticeShownAt",
            expiredPromptDates: "\(prefix).expiredPromptDates"
        )
    }
}

/// Pure pacing over `KikiAccessState` and persisted presentation history.
///
/// Call `nextPrompt` at a moment the app considers appropriate, present the
/// returned prompt, then call `recordPresented`. Nothing is recorded by
/// asking, so a host that decides not to present loses nothing.
@MainActor
public final class KikiAccessPromptSchedule {
    public let rules: KikiAccessPromptRules
    private let defaults: UserDefaults
    private let keys: KikiAccessPromptStorageKeys
    private let now: () -> Date

    public init(
        rules: KikiAccessPromptRules = .recommended,
        defaults: UserDefaults = .standard,
        keys: KikiAccessPromptStorageKeys,
        now: @escaping () -> Date = Date.init
    ) {
        self.rules = rules
        self.defaults = defaults
        self.keys = keys
        self.now = now
    }

    /// The prompt that is due, or `nil`.
    ///
    /// Only an authoritative (`ready`) readiness qualifies: a missing
    /// entitlement during loading or a degraded refresh is not proof that the
    /// user is unpaid.
    public func nextPrompt(status: KikiAccessState, readiness: KikiAccessReadiness) -> KikiAccessPrompt? {
        guard readiness.allowsAutomaticPresentation else { return nil }

        switch status {
        case .trial(.time(let daysRemaining, let expiresAt)):
            guard let notice = rules.trialEndingNotice,
                  defaults.object(forKey: keys.trialEndingNoticeShownAt) == nil,
                  expiresAt.timeIntervalSince(now()) <= notice else {
                return nil
            }
            return .trialEndingSoon(daysRemaining: daysRemaining)

        case .expired:
            let dates = expiredPromptDates
            guard dates.count < rules.maximumExpiredPrompts else { return nil }
            if let last = dates.max() {
                guard let interval = rules.expiredRepeatInterval,
                      now().timeIntervalSince(last) >= interval else {
                    return nil
                }
            }
            return .trialEnded

        case .notStarted, .trial(.usage), .pro:
            return nil
        }
    }

    public func recordPresented(_ prompt: KikiAccessPrompt) {
        switch prompt {
        case .trialEndingSoon:
            defaults.set(now(), forKey: keys.trialEndingNoticeShownAt)
        case .trialEnded:
            defaults.set(expiredPromptDates + [now()], forKey: keys.expiredPromptDates)
        }
    }

    /// Number of automatic expiry prompts already shown.
    public var expiredPromptCount: Int {
        expiredPromptDates.count
    }

    public func reset() {
        defaults.removeObject(forKey: keys.trialEndingNoticeShownAt)
        defaults.removeObject(forKey: keys.expiredPromptDates)
    }

    private var expiredPromptDates: [Date] {
        defaults.array(forKey: keys.expiredPromptDates) as? [Date] ?? []
    }
}
