import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Plain-value snapshot of an `NSScreen`, taken by the shell. Keeping AppKit out of
/// here lets every layout rule be unit tested, including displays we don't own.
///
/// All rects use AppKit global coordinates: origin bottom-left, y grows upwards.
public struct DisplayGeometry: Equatable, Sendable {
    /// `NSScreen.frame`.
    public var frame: CGRect
    /// `NSScreen.safeAreaInsets.top`. Greater than zero on notched built-in displays.
    public var safeAreaTop: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea?.width`: menu bar space left of the notch.
    public var auxiliaryTopLeftWidth: CGFloat?
    /// `NSScreen.auxiliaryTopRightArea?.width`: menu bar space right of the notch.
    public var auxiliaryTopRightWidth: CGFloat?
    /// `frame.maxY - visibleFrame.maxY`. Zero when the menu bar is hidden.
    public var menuBarHeight: CGFloat
    /// Height of the Mac's real notch, if any connected display has one. Displays
    /// without a notch copy it so every island is exactly notch height.
    public var referenceNotchHeight: CGFloat?

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftWidth: CGFloat? = nil,
        auxiliaryTopRightWidth: CGFloat? = nil,
        menuBarHeight: CGFloat = 0,
        referenceNotchHeight: CGFloat? = nil
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
        self.menuBarHeight = menuBarHeight
        self.referenceNotchHeight = referenceNotchHeight
    }
}

/// Per-display user adjustments from Settings. Keyed by the display's UUID.
public struct NotchTuning: Hashable, Sendable, Codable {
    public var widthAdjustment: Double
    public var heightAdjustment: Double
    public var horizontalOffset: Double

    public init(widthAdjustment: Double = 0, heightAdjustment: Double = 0, horizontalOffset: Double = 0) {
        self.widthAdjustment = widthAdjustment
        self.heightAdjustment = heightAdjustment
        self.horizontalOffset = horizontalOffset
    }

    public static let none = NotchTuning()
}

/// Sizes for each state. Defaults are starting points to tune on real hardware,
/// not measured values.
public struct IslandLayout: Hashable, Sendable, Codable {
    /// Collapsed island width on displays without a notch.
    public var virtualNotchWidth: Double
    /// Last-resort height on displays without a notch, used only when there is no real
    /// notch to copy and the menu bar is hidden.
    public var virtualNotchHeight: Double
    /// Gap between the top of a non-notch display and the island. 0 = flush, notch-like.
    public var virtualTopMargin: Double
    /// Extra width added on each side of the notch in `.peek`.
    public var peekWingWidth: Double
    public var expandedWidth: Double
    public var expandedHeight: Double
    public var panelWidth: Double
    public var panelHeight: Double

    public init(
        virtualNotchWidth: Double = 190,
        virtualNotchHeight: Double = 32,
        virtualTopMargin: Double = 0,
        peekWingWidth: Double = 70,
        expandedWidth: Double = 540,
        expandedHeight: Double = 180,
        panelWidth: Double = 720,
        panelHeight: Double = 400
    ) {
        self.virtualNotchWidth = virtualNotchWidth
        self.virtualNotchHeight = virtualNotchHeight
        self.virtualTopMargin = virtualTopMargin
        self.peekWingWidth = peekWingWidth
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
    }
}

public struct NotchShape: Equatable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// A physical camera housing. The island grows out of it.
        case hardware
        /// No notch: the island floats at the top centre.
        case virtual
    }

    public var kind: Kind
    public var rect: CGRect
}

public enum NotchGeometry {
    /// Detects the hardware notch from safe-area and auxiliary-area metrics, or
    /// falls back to a virtual island. Tuning applies to both.
    public static func notch(
        on display: DisplayGeometry,
        tuning: NotchTuning = .none,
        layout: IslandLayout = IslandLayout()
    ) -> NotchShape {
        let frame = display.frame

        if display.safeAreaTop > 0,
           let left = display.auxiliaryTopLeftWidth,
           let right = display.auxiliaryTopRightWidth
        {
            let width = frame.width - left - right
            if width > 0 {
                let rect = CGRect(
                    x: frame.minX + left,
                    y: frame.maxY - display.safeAreaTop,
                    width: width,
                    height: display.safeAreaTop
                )
                return NotchShape(kind: .hardware, rect: apply(tuning, to: rect, within: frame, topAnchoredAt: frame.maxY))
            }
        }

        let width = CGFloat(layout.virtualNotchWidth)
        // Exactly notch height: copy the real notch, else match the menu bar it replaces.
        let height = display.referenceNotchHeight
            ?? (display.menuBarHeight > 0 ? display.menuBarHeight : CGFloat(layout.virtualNotchHeight))
        let top = frame.maxY - CGFloat(layout.virtualTopMargin)
        let rect = CGRect(x: frame.midX - width / 2, y: top - height, width: width, height: height)
        return NotchShape(kind: .virtual, rect: apply(tuning, to: rect, within: frame, topAnchoredAt: top))
    }

    /// The island's rect for a state. Top edge stays pinned to the notch, the shape
    /// grows downwards and outwards from the notch's centre, and is clamped on screen.
    public static func islandFrame(
        for state: IslandState,
        on display: DisplayGeometry,
        tuning: NotchTuning = .none,
        layout: IslandLayout = IslandLayout()
    ) -> CGRect {
        let base = notch(on: display, tuning: tuning, layout: layout).rect
        let size: CGSize
        switch state {
        case .hidden, .collapsed:
            return base
        case .peek:
            size = CGSize(width: base.width + 2 * CGFloat(layout.peekWingWidth), height: base.height)
        case .expanded:
            size = CGSize(
                width: max(base.width, CGFloat(layout.expandedWidth)),
                height: max(base.height, CGFloat(layout.expandedHeight))
            )
        case .panel:
            size = CGSize(
                width: max(base.width, CGFloat(layout.panelWidth)),
                height: max(base.height, CGFloat(layout.panelHeight))
            )
        }
        let rect = CGRect(x: base.midX - size.width / 2, y: base.maxY - size.height, width: size.width, height: size.height)
        return clampHorizontally(rect, within: display.frame)
    }

    /// The panel window's fixed frame: big enough for every state. The window is
    /// never resized during animation (resizing an NSWindow per frame stutters);
    /// SwiftUI animates the shape inside it and hit-testing ignores the empty area.
    public static func windowFrame(
        on display: DisplayGeometry,
        tuning: NotchTuning = .none,
        layout: IslandLayout = IslandLayout()
    ) -> CGRect {
        IslandState.allCases
            .map { islandFrame(for: $0, on: display, tuning: tuning, layout: layout) }
            .reduce(CGRect.null) { $0.union($1) }
    }

    // MARK: - Helpers

    private static func apply(_ tuning: NotchTuning, to rect: CGRect, within frame: CGRect, topAnchoredAt top: CGFloat) -> CGRect {
        let width = max(1, rect.width + CGFloat(tuning.widthAdjustment))
        let height = max(1, rect.height + CGFloat(tuning.heightAdjustment))
        let midX = rect.midX + CGFloat(tuning.horizontalOffset)
        let adjusted = CGRect(x: midX - width / 2, y: top - height, width: width, height: height)
        return clampHorizontally(adjusted, within: frame)
    }

    private static func clampHorizontally(_ rect: CGRect, within frame: CGRect) -> CGRect {
        var result = rect
        if result.width > frame.width {
            result.size.width = frame.width
            result.origin.x = frame.minX
            return result
        }
        if result.minX < frame.minX { result.origin.x = frame.minX }
        if result.maxX > frame.maxX { result.origin.x = frame.maxX - result.width }
        return result
    }
}
