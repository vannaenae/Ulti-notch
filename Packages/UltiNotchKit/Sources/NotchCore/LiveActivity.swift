import Foundation

/// Priority classes. A higher class always beats a lower one. User ranking only
/// reorders activities *within* a class, so a user can put music above downloads
/// but can never hide an incoming call behind a battery indicator.
public enum ActivityPriority: Int, Hashable, Sendable, Codable, Comparable, CaseIterable {
    /// Ambient state, e.g. battery level while not charging.
    case background = 0
    /// Useful but passive, e.g. a download in progress.
    case low = 1
    /// The default, e.g. media playing, timer running.
    case normal = 2
    /// Short, important changes, e.g. AirPods connected, timer finished.
    case high = 3
    /// Needs the user now, e.g. incoming call, AI agent approval request.
    case critical = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Semantic colour tokens. The appearance layer maps them to real colours, so
/// modules and future plugins can't break the visual system.
public enum Tint: String, Hashable, Sendable, Codable {
    case primary, secondary, accent, positive, warning, critical
}

/// Declarative content for one side of the compact island.
///
/// Deliberately data-only and `Codable`: first-party modules may also supply a
/// custom SwiftUI view, but sandboxed plugins (Phase 4) will run out of process and
/// can only send values like these across the boundary.
public enum Glyph: Hashable, Sendable, Codable {
    case none
    case symbol(String, tint: Tint = .primary)
    case text(String, tint: Tint = .primary)
    /// Ring, 0...1. Downloads, timers.
    case progress(Double, tint: Tint = .accent)
    /// Horizontal level bar, 0...1. Volume, brightness.
    case level(Double, tint: Tint = .primary)
    /// Image owned by the host's artwork cache, referenced by key.
    case artwork(key: String)
    /// Animated audio bars.
    case equalizer(isPlaying: Bool)
    /// Live countdown rendered by the host, so the module doesn't need a timer.
    case countdown(to: Date, tint: Tint = .primary)
}

public struct ActivityContent: Hashable, Sendable, Codable {
    /// Left of the notch.
    public var leading: Glyph
    /// Right of the notch.
    public var trailing: Glyph
    /// Read by VoiceOver.
    public var accessibilityLabel: String

    public init(leading: Glyph, trailing: Glyph, accessibilityLabel: String) {
        self.leading = leading
        self.trailing = trailing
        self.accessibilityLabel = accessibilityLabel
    }
}

/// How long an activity lives.
public enum ActivityLifetime: Hashable, Sendable, Codable {
    /// Until the module withdraws it (media playing, download running).
    case ongoing
    /// Auto-expires. Used for brief interruptions such as "AirPods connected" or a HUD change.
    case transient(seconds: Double)
}

public struct LiveActivity: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        public let module: ModuleID
        /// Module-scoped key. A module can run several activities (two downloads).
        public let key: String
        public init(module: ModuleID, key: String) {
            self.module = module
            self.key = key
        }
        public var description: String { "\(module.rawValue)#\(key)" }
    }

    public let id: ID
    public var priority: ActivityPriority
    public var lifetime: ActivityLifetime
    public var content: ActivityContent
    /// Ask the island to briefly enlarge when this activity starts or changes materially.
    public var requestsPeek: Bool
    /// Set by the board, not the module.
    public internal(set) var startedAt: Date
    public internal(set) var updatedAt: Date

    public init(
        id: ID,
        priority: ActivityPriority,
        lifetime: ActivityLifetime = .ongoing,
        content: ActivityContent,
        requestsPeek: Bool = false,
        startedAt: Date = .distantPast
    ) {
        self.id = id
        self.priority = priority
        self.lifetime = lifetime
        self.content = content
        self.requestsPeek = requestsPeek
        self.startedAt = startedAt
        self.updatedAt = startedAt
    }

    public var isTransient: Bool {
        if case .transient = lifetime { return true }
        return false
    }

    /// When a transient activity stops being eligible. Measured from the last update,
    /// so repeated volume key presses keep the HUD on screen.
    public var expiresAt: Date? {
        guard case .transient(let seconds) = lifetime else { return nil }
        return updatedAt.addingTimeInterval(seconds)
    }

    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}
