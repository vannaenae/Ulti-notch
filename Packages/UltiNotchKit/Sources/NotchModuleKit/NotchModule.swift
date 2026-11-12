@_exported import NotchCore
import SwiftUI

/// The full module protocol: lifecycle (from NotchCore) plus SwiftUI surfaces.
///
/// Rules every module follows:
/// - Talk to the system only through services acquired from `ModuleContext`.
/// - Do nothing in `init`. Real work starts in `activate`, so a constructed but
///   inactive module costs nothing.
/// - Return views only for surfaces declared in the descriptor.
/// - Views read state the module already holds. No polling inside views. Use
///   `TimelineView` only for content that is on screen.
///
/// Views are type-erased with `AnyView` so the host can hold modules of different
/// types. That costs nothing that matters at one view per module per surface.
@MainActor
public protocol NotchModule: ModuleLifecycle {
    /// Custom compact content for one of this module's activities. Return nil to let the
    /// host render the activity's declarative `ActivityContent` (the default).
    func compactView(for activity: LiveActivity, side: CompactSide) -> AnyView?

    /// Content for the expanded island.
    func expandedView() -> AnyView?

    /// Content for the full shelf.
    func panelView() -> AnyView?

    /// Small widget the user can place and reorder in the full shelf.
    func shelfWidgetView() -> AnyView?

    /// Run a command from the descriptor's `commands`. Only called while active; the
    /// palette enables the module first if needed.
    func perform(command id: String) async

    /// Lock screen widget (Phase 3).
    func lockScreenView() -> AnyView?

    /// Section for the Settings window. Static because Settings shows it while the module
    /// is disabled, and disabled modules are never instantiated. It reads and writes
    /// persisted settings only; a running module observes those settings.
    static func settingsView() -> AnyView?
}

public enum CompactSide: String, Hashable, Sendable {
    case leading, trailing
}

public extension NotchModule {
    func compactView(for activity: LiveActivity, side: CompactSide) -> AnyView? { nil }
    func expandedView() -> AnyView? { nil }
    func panelView() -> AnyView? { nil }
    func shelfWidgetView() -> AnyView? { nil }
    func perform(command id: String) async {}
    func lockScreenView() -> AnyView? { nil }
    static func settingsView() -> AnyView? { nil }
}
