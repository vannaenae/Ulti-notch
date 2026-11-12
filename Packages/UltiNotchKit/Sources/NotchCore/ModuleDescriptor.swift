import Foundation

/// Stable, reverse-DNS identifier for a module, e.g. `app.ultinotch.media`.
///
/// IDs are persisted in settings and exported files, so they must never change
/// once a module has shipped. Third-party modules will use their own reverse-DNS prefix.
public struct ModuleID: RawRepresentable, Hashable, Sendable, Codable, Comparable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: ModuleID, rhs: ModuleID) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Lowercase reverse-DNS with at least three components. Kept strict so IDs stay
    /// usable as UserDefaults keys, file names and XPC service names later.
    public var isWellFormed: Bool {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(allowed.contains) }
    }
}

/// The UI surfaces a module can provide. The host only asks a module for a view
/// on a surface the module declared.
public struct ModuleSurfaces: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Leading/trailing content around the notch while a live activity runs.
    public static let compact = ModuleSurfaces(rawValue: 1 << 0)
    /// A page or tile inside the expanded island.
    public static let expanded = ModuleSurfaces(rawValue: 1 << 1)
    /// Content for the full panel state.
    public static let panel = ModuleSurfaces(rawValue: 1 << 2)
    /// Lock screen widget (Phase 3).
    public static let lockScreen = ModuleSurfaces(rawValue: 1 << 3)
    /// A section in the Settings window.
    public static let settings = ModuleSurfaces(rawValue: 1 << 4)
}

/// Everything the host needs to know about a module *without instantiating it*.
///
/// The Settings window, onboarding and permission flow all read descriptors only.
/// A disabled module is never constructed, which is how "disabled modules use zero
/// resources" is enforced structurally rather than by convention.
public struct ModuleDescriptor: Hashable, Sendable, Codable, Identifiable {
    public let id: ModuleID
    public var name: String
    public var summary: String
    /// SF Symbol name used in Settings and onboarding.
    public var symbolName: String
    public var surfaces: ModuleSurfaces
    public var permissions: [PermissionRequirement]
    /// Services the module will acquire. Lets Settings explain resource use and lets
    /// the host pre-validate that every service is registered.
    public var services: [String]
    /// Default priority class for this module's live activities.
    public var defaultPriority: ActivityPriority
    public var enabledByDefault: Bool
    /// True if any part of the module talks to the network. Network modules are
    /// always opt-in (see `validationIssues`).
    public var usesNetwork: Bool
    /// True if the module depends on a private framework or another unsupported path.
    /// Surfaced in Settings so users can see what is experimental.
    public var usesPrivateAPI: Bool

    public init(
        id: ModuleID,
        name: String,
        summary: String,
        symbolName: String,
        surfaces: ModuleSurfaces,
        permissions: [PermissionRequirement] = [],
        services: [String] = [],
        defaultPriority: ActivityPriority = .normal,
        enabledByDefault: Bool = false,
        usesNetwork: Bool = false,
        usesPrivateAPI: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.surfaces = surfaces
        self.permissions = permissions
        self.services = services
        self.defaultPriority = defaultPriority
        self.enabledByDefault = enabledByDefault
        self.usesNetwork = usesNetwork
        self.usesPrivateAPI = usesPrivateAPI
    }

    /// Product rules that every descriptor must satisfy. Checked in unit tests for
    /// every first-party module and at registration time for everything else.
    public var validationIssues: [ModuleValidationIssue] {
        var issues: [ModuleValidationIssue] = []
        if !id.isWellFormed { issues.append(.malformedID) }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.missingName) }
        if surfaces.isEmpty { issues.append(.noSurfaces) }
        // First launch must need zero permissions.
        if enabledByDefault && permissions.contains(where: \.isRequired) {
            issues.append(.enabledByDefaultButNeedsPermission)
        }
        // User data stays on device unless the user opts in.
        if enabledByDefault && usesNetwork { issues.append(.enabledByDefaultButUsesNetwork) }
        if permissions.contains(where: { $0.reason.trimmingCharacters(in: .whitespaces).isEmpty }) {
            issues.append(.permissionWithoutReason)
        }
        return issues
    }
}

public enum ModuleValidationIssue: String, Hashable, Sendable, Codable {
    case malformedID
    case missingName
    case noSurfaces
    case enabledByDefaultButNeedsPermission
    case enabledByDefaultButUsesNetwork
    case permissionWithoutReason
}
