import Foundation

/// macOS privacy permissions (TCC) and similar consent gates the app may need.
public enum PermissionKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// Event taps that modify or swallow events (HUD replacement), window management.
    case accessibility
    /// Listen-only event taps.
    case inputMonitoring
    /// Apple Events to a specific app (Music, Spotify). Needs `target`.
    case automation
    case calendars
    case reminders
    case bluetooth
    case camera
    case microphone
    /// Screen and system audio recording (real audio visualizer, screen recording module).
    case screenRecording
    case notifications
    case location
}

/// A permission a module needs, with the user-facing reason shown *before* the system
/// prompt. Requests happen only when the user enables the feature that needs them.
public struct PermissionRequirement: Hashable, Sendable, Codable {
    public var kind: PermissionKind
    /// Bundle identifier for `.automation`, otherwise nil.
    public var target: String?
    /// One plain sentence: what the feature does with this access.
    public var reason: String
    /// False when the module works without it and the permission only adds a capability
    /// (for example, playback controls on top of read-only track info).
    public var isRequired: Bool

    public init(_ kind: PermissionKind, target: String? = nil, reason: String, isRequired: Bool = true) {
        self.kind = kind
        self.target = target
        self.reason = reason
        self.isRequired = isRequired
    }
}

public enum PermissionStatus: String, Hashable, Sendable, Codable {
    case notDetermined
    case granted
    case denied
    /// Blocked by MDM or parental controls.
    case restricted
}
