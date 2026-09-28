import Foundation
@testable import KikiCommerceCore
import Testing

@MainActor
struct KikiAccessPromptScheduleTests {
    private let day: TimeInterval = 24 * 60 * 60

    @Test("Trial-ending notice is due once inside the notice window")
    func trialEndingNotice() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let (schedule, cleanup) = makeSchedule(now: { now })
        defer { cleanup() }
        let expiresAt = now.addingTimeInterval(5 * day)

        #expect(schedule.nextPrompt(status: .trial(.time(daysRemaining: 5, expiresAt: expiresAt)), readiness: .ready) == nil)

        now = expiresAt.addingTimeInterval(-2 * day)
        let due = schedule.nextPrompt(status: .trial(.time(daysRemaining: 2, expiresAt: expiresAt)), readiness: .ready)
        #expect(due == .trialEndingSoon(daysRemaining: 2))

        schedule.recordPresented(.trialEndingSoon(daysRemaining: 2))
        now = expiresAt.addingTimeInterval(-3_600)
        #expect(schedule.nextPrompt(status: .trial(.time(daysRemaining: 1, expiresAt: expiresAt)), readiness: .ready) == nil)
    }

    @Test("Expiry prompts repeat on the interval and stop at the cap")
    func expiredPromptsAreCapped() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let (schedule, cleanup) = makeSchedule(now: { now })
        defer { cleanup() }

        for _ in 0..<3 {
            #expect(schedule.nextPrompt(status: .expired, readiness: .ready) == .trialEnded)
            schedule.recordPresented(.trialEnded)
            #expect(schedule.nextPrompt(status: .expired, readiness: .ready) == nil)
            now = now.addingTimeInterval(day)
        }

        #expect(schedule.expiredPromptCount == 3)
        #expect(schedule.nextPrompt(status: .expired, readiness: .ready) == nil)
    }

    @Test("A nil repeat interval allows exactly one expiry prompt")
    func singleExpiryPrompt() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let rules = KikiAccessPromptRules(trialEndingNotice: nil, expiredRepeatInterval: nil, maximumExpiredPrompts: 5)
        let (schedule, cleanup) = makeSchedule(rules: rules, now: { now })
        defer { cleanup() }

        #expect(schedule.nextPrompt(status: .expired, readiness: .ready) == .trialEnded)
        schedule.recordPresented(.trialEnded)
        now = now.addingTimeInterval(30 * day)
        #expect(schedule.nextPrompt(status: .expired, readiness: .ready) == nil)
    }

    @Test("Only an authoritative readiness may prompt")
    func readinessGate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (schedule, cleanup) = makeSchedule(now: { now })
        defer { cleanup() }

        #expect(schedule.nextPrompt(status: .expired, readiness: .loading) == nil)
        #expect(schedule.nextPrompt(status: .expired, readiness: .degraded(message: "offline")) == nil)
        #expect(schedule.nextPrompt(status: .notStarted, readiness: .ready) == nil)
    }

    @Test("Asking records nothing; reset clears history")
    func askingIsSideEffectFree() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (schedule, cleanup) = makeSchedule(now: { now })
        defer { cleanup() }

        _ = schedule.nextPrompt(status: .expired, readiness: .ready)
        _ = schedule.nextPrompt(status: .expired, readiness: .ready)
        #expect(schedule.expiredPromptCount == 0)

        schedule.recordPresented(.trialEnded)
        schedule.reset()
        #expect(schedule.expiredPromptCount == 0)
        #expect(schedule.nextPrompt(status: .expired, readiness: .ready) == .trialEnded)
    }

    private func makeSchedule(
        rules: KikiAccessPromptRules = .recommended,
        now: @escaping () -> Date
    ) -> (KikiAccessPromptSchedule, () -> Void) {
        let suiteName = "KikiAccessPromptScheduleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let schedule = KikiAccessPromptSchedule(
            rules: rules,
            defaults: defaults,
            keys: .prefixed("test.prompts"),
            now: now
        )
        return (schedule, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
