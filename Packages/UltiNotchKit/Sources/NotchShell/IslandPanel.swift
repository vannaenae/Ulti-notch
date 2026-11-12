import AppKit

/// Borderless, non-activating panel that sits above the menu bar on every Space.
final class IslandPanel: NSPanel {
    convenience init(frame: CGRect) {
        self.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // ponytail: mainMenu + 3 draws over the menu bar; verify against macOS 26's menu bar on hardware.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }

    /// Without this, AppKit pushes the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
