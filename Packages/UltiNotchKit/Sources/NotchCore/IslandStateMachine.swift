import Foundation

/// Presentation states of one island (one per display).
public enum IslandState: String, Hashable, Sendable, Codable, CaseIterable {
    /// Not shown: full-screen app (if the user hides there), display asleep, screen locked.
    case hidden
    /// Matches the hardware notch, or a small pill on displays without one. Nothing to show.
    case collapsed
    /// Compact live activity around the notch (leading and trailing content).
    case peek
    /// Hover or click: modules' expanded views.
    case expanded
    /// Full panel: shelf, calendar month grid, settings shortcuts. Stays until dismissed.
    case panel

    public var isOpen: Bool { self == .expanded || self == .panel }
}

public enum IslandShortcut: String, Hashable, Sendable, Codable {
    case toggleExpanded
    case togglePanel
}

public enum IslandTimer: String, Hashable, Sendable, Codable {
    /// Pointer has to rest on the island this long before it expands. Avoids
    /// accidental opens when the cursor passes through the menu bar.
    case hoverIntent
    /// Grace period after the pointer leaves before collapsing. Stops flicker when
    /// the pointer clips the edge.
    case collapseGrace
    /// How long an activity peek stays enlarged before settling.
    case peekSettle
}

public enum IslandEvent: Hashable, Sendable {
    case pointerEntered
    case pointerExited
    /// Click on the island background (controls inside the island handle their own clicks).
    case clicked
    case swipedDown
    case swipedUp
    case shortcut(IslandShortcut)
    case escapePressed
    case clickedOutside
    /// A file drag entered the island's drop zone.
    case dragEntered
    case dragExited
    case dropCompleted
    /// Whether any live activity is available for this display.
    case activityAvailabilityChanged(Bool)
    /// A new activity asked to be noticed (`LiveActivity.requestsPeek`).
    case activityRequestedAttention
    /// Full-screen app, lock screen or display sleep started (true) or ended (false).
    case suppressionChanged(Bool)
    case timerFired(IslandTimer)
}

public enum IslandEffect: Hashable, Sendable {
    case startTimer(IslandTimer, seconds: Double)
    case cancelTimer(IslandTimer)
}

/// User-tunable timing and triggers. All persisted, all exportable.
public struct IslandBehavior: Hashable, Sendable, Codable {
    public var expandsOnHover: Bool
    public var hoverIntentDelay: Double
    public var collapseDelay: Double
    public var collapsesOnPointerExit: Bool
    public var expandsOnClick: Bool
    public var swipeGesturesEnabled: Bool
    /// Seconds a requested peek stays enlarged. 0 disables attention peeks.
    public var attentionDuration: Double

    public init(
        expandsOnHover: Bool = true,
        hoverIntentDelay: Double = 0.15,
        collapseDelay: Double = 0.4,
        collapsesOnPointerExit: Bool = true,
        expandsOnClick: Bool = true,
        swipeGesturesEnabled: Bool = true,
        attentionDuration: Double = 2.5
    ) {
        self.expandsOnHover = expandsOnHover
        self.hoverIntentDelay = hoverIntentDelay
        self.collapseDelay = collapseDelay
        self.collapsesOnPointerExit = collapsesOnPointerExit
        self.expandsOnClick = expandsOnClick
        self.swipeGesturesEnabled = swipeGesturesEnabled
        self.attentionDuration = attentionDuration
    }
}

/// Pure reducer for one island. No clocks, no AppKit: the shell feeds events in,
/// runs the returned timer effects, and renders `state`.
public struct IslandStateMachine: Hashable, Sendable {
    public private(set) var state: IslandState
    public private(set) var hasActivity: Bool = false
    public private(set) var isPointerInside: Bool = false
    public private(set) var isDragging: Bool = false
    public private(set) var isSuppressed: Bool = false
    /// True while an attention peek is showing. The view renders `.peek` larger.
    public private(set) var isAttentionPeek: Bool = false
    public var behavior: IslandBehavior

    public init(behavior: IslandBehavior = IslandBehavior()) {
        self.behavior = behavior
        self.state = .collapsed
    }

    /// Where the island returns to when nothing is open.
    public var restingState: IslandState {
        if isSuppressed { return .hidden }
        return hasActivity ? .peek : .collapsed
    }

    @discardableResult
    public mutating func handle(_ event: IslandEvent) -> [IslandEffect] {
        switch event {
        case .suppressionChanged(let suppressed):
            return setSuppressed(suppressed)

        case .activityAvailabilityChanged(let available):
            hasActivity = available
            if !available { isAttentionPeek = false }
            if !state.isOpen { state = restingState }
            return available ? [] : [.cancelTimer(.peekSettle)]

        case .activityRequestedAttention:
            guard !isSuppressed, !state.isOpen, hasActivity, behavior.attentionDuration > 0 else { return [] }
            state = .peek
            isAttentionPeek = true
            return [.startTimer(.peekSettle, seconds: behavior.attentionDuration)]

        case .pointerEntered:
            guard !isSuppressed else { return [] }
            isPointerInside = true
            var effects: [IslandEffect] = [.cancelTimer(.collapseGrace)]
            if !state.isOpen && behavior.expandsOnHover {
                if behavior.hoverIntentDelay <= 0 {
                    effects += open(.expanded)
                } else {
                    effects.append(.startTimer(.hoverIntent, seconds: behavior.hoverIntentDelay))
                }
            }
            return effects

        case .pointerExited:
            isPointerInside = false
            var effects: [IslandEffect] = [.cancelTimer(.hoverIntent)]
            effects += scheduleCollapseIfIdle()
            return effects

        case .clicked:
            guard !isSuppressed, behavior.expandsOnClick, !state.isOpen else { return [] }
            return open(.expanded)

        case .swipedDown:
            guard !isSuppressed, behavior.swipeGesturesEnabled else { return [] }
            switch state {
            case .collapsed, .peek: return open(.expanded)
            case .expanded: return open(.panel)
            case .panel, .hidden: return []
            }

        case .swipedUp:
            guard behavior.swipeGesturesEnabled else { return [] }
            switch state {
            case .panel:
                state = .expanded
                return scheduleCollapseIfIdle()
            case .expanded: return close()
            case .collapsed, .peek, .hidden: return []
            }

        case .shortcut(.toggleExpanded):
            guard !isSuppressed else { return [] }
            return state.isOpen ? close() : open(.expanded)

        case .shortcut(.togglePanel):
            guard !isSuppressed else { return [] }
            return state == .panel ? close() : open(.panel)

        case .escapePressed, .clickedOutside:
            guard state.isOpen else { return [] }
            return close()

        case .dragEntered:
            guard !isSuppressed else { return [] }
            isDragging = true
            var effects: [IslandEffect] = [.cancelTimer(.collapseGrace)]
            if !state.isOpen { effects += open(.expanded) }
            return effects

        case .dragExited:
            isDragging = false
            return scheduleCollapseIfIdle()

        case .dropCompleted:
            isDragging = false
            return scheduleCollapseIfIdle()

        case .timerFired(.hoverIntent):
            guard isPointerInside, !isSuppressed, !state.isOpen else { return [] }
            return open(.expanded)

        case .timerFired(.collapseGrace):
            guard state == .expanded, !isPointerInside, !isDragging else { return [] }
            return close()

        case .timerFired(.peekSettle):
            isAttentionPeek = false
            return []
        }
    }

    // MARK: - Transitions

    private mutating func open(_ target: IslandState) -> [IslandEffect] {
        state = target
        isAttentionPeek = false
        return [.cancelTimer(.hoverIntent), .cancelTimer(.peekSettle)]
    }

    private mutating func close() -> [IslandEffect] {
        state = restingState
        return [.cancelTimer(.hoverIntent), .cancelTimer(.collapseGrace)]
    }

    /// Only `.expanded` auto-collapses. `.panel` is deliberate and stays until dismissed.
    private func scheduleCollapseIfIdle() -> [IslandEffect] {
        guard state == .expanded, behavior.collapsesOnPointerExit, !isPointerInside, !isDragging else { return [] }
        return [.startTimer(.collapseGrace, seconds: behavior.collapseDelay)]
    }

    private mutating func setSuppressed(_ suppressed: Bool) -> [IslandEffect] {
        isSuppressed = suppressed
        if suppressed {
            isPointerInside = false
            isDragging = false
            isAttentionPeek = false
            state = .hidden
            return [.cancelTimer(.hoverIntent), .cancelTimer(.collapseGrace), .cancelTimer(.peekSettle)]
        }
        state = restingState
        return []
    }
}
