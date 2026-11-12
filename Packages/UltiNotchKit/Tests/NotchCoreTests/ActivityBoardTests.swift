import Foundation
import Testing
@testable import NotchCore

@Suite("Live activity arbitration")
struct ActivityBoardTests {
    let media: ModuleID = "app.ultinotch.media"
    let battery: ModuleID = "app.ultinotch.battery"
    let downloads: ModuleID = "app.ultinotch.downloads"
    let calls: ModuleID = "app.ultinotch.calls"
    let hud: ModuleID = "app.ultinotch.hud"

    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func activity(
        _ module: ModuleID,
        _ priority: ActivityPriority,
        key: String = "main",
        lifetime: ActivityLifetime = .ongoing
    ) -> LiveActivity {
        LiveActivity(
            id: .init(module: module, key: key),
            priority: priority,
            lifetime: lifetime,
            content: ActivityContent(leading: .none, trailing: .none, accessibilityLabel: module.rawValue)
        )
    }

    @Test func emptyBoardResolvesToNothing() {
        #expect(ActivityBoard().resolve(now: t0, policy: .init()) == .empty)
    }

    @Test func higherClassWins() {
        var board = ActivityBoard()
        board.upsert(activity(battery, .background), now: t0)
        board.upsert(activity(media, .normal), now: t0)
        let r = board.resolve(now: t0, policy: .init())
        #expect(r.primary?.id.module == media)
        #expect(r.secondary == nil) // battery is below the secondary threshold
    }

    @Test func criticalBeatsPinned() {
        var board = ActivityBoard()
        board.upsert(activity(media, .normal), now: t0)
        board.upsert(activity(calls, .critical), now: t0)
        let r = board.resolve(now: t0, policy: .init(pinnedModule: media))
        #expect(r.primary?.id.module == calls)
        #expect(r.secondary?.id.module == media)
    }

    @Test func pinnedBeatsHigherNonCriticalClass() {
        var board = ActivityBoard()
        board.upsert(activity(media, .normal), now: t0)
        board.upsert(activity(hud, .high, lifetime: .transient(seconds: 2)), now: t0)
        let r = board.resolve(now: t0, policy: .init(pinnedModule: media))
        #expect(r.primary?.id.module == media)
    }

    @Test func userRankingBreaksTiesWithinAClass() {
        var board = ActivityBoard()
        board.upsert(activity(media, .normal), now: t0)
        board.upsert(activity(downloads, .normal), now: t0.addingTimeInterval(1))

        // Without ranking, most recent wins.
        #expect(board.resolve(now: t0, policy: .init()).primary?.id.module == downloads)
        // With ranking, the user's order wins.
        let ranked = ArbitrationPolicy(moduleRanking: [media, downloads])
        #expect(board.resolve(now: t0, policy: ranked).primary?.id.module == media)
    }

    @Test func rankingNeverCrossesClasses() {
        var board = ActivityBoard()
        board.upsert(activity(battery, .low), now: t0)
        board.upsert(activity(media, .normal), now: t0)
        let policy = ArbitrationPolicy(moduleRanking: [battery, media])
        #expect(board.resolve(now: t0, policy: policy).primary?.id.module == media)
    }

    @Test func transientInterruptsThenExpires() {
        var board = ActivityBoard()
        board.upsert(activity(media, .normal), now: t0)
        board.upsert(activity(battery, .normal, key: "plugged", lifetime: .transient(seconds: 3)), now: t0)

        let during = board.resolve(now: t0.addingTimeInterval(1), policy: .init())
        #expect(during.primary?.id.module == battery)
        #expect(during.nextChange == t0.addingTimeInterval(3))

        let after = board.resolve(now: t0.addingTimeInterval(3), policy: .init())
        #expect(after.primary?.id.module == media)
        #expect(after.nextChange == nil)
    }

    @Test func updatingTransientExtendsItButKeepsStartTime() {
        var board = ActivityBoard()
        let volume = activity(hud, .high, key: "volume", lifetime: .transient(seconds: 1.5))
        board.upsert(volume, now: t0)
        board.upsert(volume, now: t0.addingTimeInterval(1))

        let stored = board.activities[volume.id]
        #expect(stored?.startedAt == t0)
        #expect(stored?.expiresAt == t0.addingTimeInterval(2.5))
        #expect(board.resolve(now: t0.addingTimeInterval(2), policy: .init()).primary?.id == volume.id)
    }

    @Test func secondaryComesFromADifferentModule() {
        var board = ActivityBoard()
        board.upsert(activity(downloads, .low, key: "a"), now: t0)
        board.upsert(activity(downloads, .low, key: "b"), now: t0)
        board.upsert(activity(media, .normal), now: t0)
        board.upsert(activity(media, .normal, key: "other"), now: t0)
        let r = board.resolve(now: t0, policy: .init())
        #expect(r.primary?.id.module == media)
        #expect(r.secondary?.id.module == downloads)
    }

    @Test func secondaryCanBeDisabled() {
        var board = ActivityBoard()
        board.upsert(activity(media, .normal), now: t0)
        board.upsert(activity(downloads, .normal), now: t0)
        #expect(board.resolve(now: t0, policy: .init(allowsSecondary: false)).secondary == nil)
    }

    @Test func withdrawAllRemovesOnlyThatModule() {
        var board = ActivityBoard()
        board.upsert(activity(downloads, .low, key: "a"), now: t0)
        board.upsert(activity(downloads, .low, key: "b"), now: t0)
        board.upsert(activity(media, .normal), now: t0)
        board.withdrawAll(from: downloads)
        #expect(board.activities.count == 1)
        #expect(board.activities.keys.first?.module == media)
    }

    @Test func resolutionIsStableForEqualCandidates() {
        var board = ActivityBoard()
        board.upsert(activity(media, .normal, key: "b"), now: t0)
        board.upsert(activity(media, .normal, key: "a"), now: t0)
        let first = board.resolve(now: t0, policy: .init())
        for _ in 0..<20 {
            #expect(board.resolve(now: t0, policy: .init()) == first)
        }
        #expect(first.primary?.id.key == "a")
    }
}
