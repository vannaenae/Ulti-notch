import Foundation

/// User-controlled arbitration settings.
public struct ArbitrationPolicy: Hashable, Sendable, Codable {
    /// Modules in the user's preferred order, most important first. Only breaks ties
    /// inside a priority class. Unlisted modules rank after listed ones.
    public var moduleRanking: [ModuleID]
    /// A module whose activity should stay primary until unpinned. A `.critical`
    /// activity still wins over a pinned one.
    public var pinnedModule: ModuleID?
    /// Show a second, smaller activity beside the primary one (split island).
    public var allowsSecondary: Bool
    /// Lowest class that can take the secondary slot. Stops ambient state
    /// (battery idle) from cluttering the island.
    public var secondaryMinimumPriority: ActivityPriority

    public init(
        moduleRanking: [ModuleID] = [],
        pinnedModule: ModuleID? = nil,
        allowsSecondary: Bool = true,
        secondaryMinimumPriority: ActivityPriority = .low
    ) {
        self.moduleRanking = moduleRanking
        self.pinnedModule = pinnedModule
        self.allowsSecondary = allowsSecondary
        self.secondaryMinimumPriority = secondaryMinimumPriority
    }
}

/// What the island should show right now.
public struct ActivityResolution: Hashable, Sendable {
    public var primary: LiveActivity?
    public var secondary: LiveActivity?
    /// Earliest moment the resolution can change on its own (a transient expiring).
    /// The host schedules exactly one timer for it, so nothing polls while idle.
    public var nextChange: Date?

    public init(primary: LiveActivity? = nil, secondary: LiveActivity? = nil, nextChange: Date? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.nextChange = nextChange
    }

    public static let empty = ActivityResolution()
}

/// Holds every live activity from every module and decides which one wins.
///
/// A value type with no clock and no timers: callers pass `now`. That keeps the
/// arbitration rules deterministic and fully unit-testable.
public struct ActivityBoard: Hashable, Sendable {
    public private(set) var activities: [LiveActivity.ID: LiveActivity] = [:]

    public init() {}

    /// Inserts or updates an activity. `startedAt` survives updates, so a playing
    /// track keeps its recency when only the scrub position changes.
    public mutating func upsert(_ activity: LiveActivity, now: Date) {
        var next = activity
        if let existing = activities[activity.id] {
            next.startedAt = existing.startedAt
        } else {
            next.startedAt = now
        }
        next.updatedAt = now
        activities[activity.id] = next
    }

    @discardableResult
    public mutating func withdraw(_ id: LiveActivity.ID) -> LiveActivity? {
        activities.removeValue(forKey: id)
    }

    /// Removes everything a module published. Called when a module is switched off.
    public mutating func withdrawAll(from module: ModuleID) {
        activities = activities.filter { $0.key.module != module }
    }

    public mutating func pruneExpired(now: Date) {
        activities = activities.filter { !$0.value.isExpired(at: now) }
    }

    public func resolve(now: Date, policy: ArbitrationPolicy) -> ActivityResolution {
        let live = activities.values.filter { !$0.isExpired(at: now) }
        guard !live.isEmpty else { return .empty }

        let ranked = live.sorted { Self.ranks($0, above: $1, policy: policy) }
        let primary = ranked[0]

        var secondary: LiveActivity?
        if policy.allowsSecondary {
            secondary = ranked.dropFirst().first {
                $0.id.module != primary.id.module && $0.priority >= policy.secondaryMinimumPriority
            }
        }

        let nextChange = live.compactMap(\.expiresAt).min()
        return ActivityResolution(primary: primary, secondary: secondary, nextChange: nextChange)
    }

    /// Ordering, most important first:
    /// 1. `.critical` beats everything, including a pinned module.
    /// 2. The pinned module.
    /// 3. Priority class.
    /// 4. Transient beats ongoing in the same class (a brief interruption, then back).
    /// 5. User module ranking.
    /// 6. Most recently started.
    /// 7. ID, so the order is stable and never flickers between equal candidates.
    static func ranks(_ a: LiveActivity, above b: LiveActivity, policy: ArbitrationPolicy) -> Bool {
        let aCritical = a.priority == .critical
        let bCritical = b.priority == .critical
        if aCritical != bCritical { return aCritical }

        if let pinned = policy.pinnedModule, !aCritical {
            let aPinned = a.id.module == pinned
            let bPinned = b.id.module == pinned
            if aPinned != bPinned { return aPinned }
        }

        if a.priority != b.priority { return a.priority > b.priority }
        if a.isTransient != b.isTransient { return a.isTransient }

        let aRank = rankIndex(of: a.id.module, in: policy.moduleRanking)
        let bRank = rankIndex(of: b.id.module, in: policy.moduleRanking)
        if aRank != bRank { return aRank < bRank }

        if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
        return a.id.description < b.id.description
    }

    private static func rankIndex(of module: ModuleID, in ranking: [ModuleID]) -> Int {
        ranking.firstIndex(of: module) ?? Int.max
    }
}
