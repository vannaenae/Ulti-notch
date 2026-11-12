import AppKit
import NotchModuleKit

/// Keeps one island per connected display. Rebuilt on display changes and on wake.
@MainActor
public final class DisplayManager {
    private let content: IslandContent
    // ponytail: keyed by CGDirectDisplayID (stable per session). Switch to display UUIDs
    // when per-display settings are persisted.
    private var islands: [CGDirectDisplayID: IslandController] = [:]
    private var observers: [NSObjectProtocol] = []

    public init(content: IslandContent) {
        self.content = content
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: handler))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler))
        rebuild()
    }

    public func resolutionChanged() {
        islands.values.forEach { $0.resolutionChanged() }
    }

    private func rebuild() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = screen.displayID
            seen.insert(id)
            if let island = islands[id] {
                island.update(screen: screen)
            } else {
                islands[id] = IslandController(screen: screen, content: content)
            }
        }
        for (id, island) in islands where !seen.contains(id) {
            island.close()
            islands[id] = nil
        }
    }
}
