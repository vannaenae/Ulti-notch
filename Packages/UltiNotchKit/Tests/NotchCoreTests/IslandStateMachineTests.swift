import Testing
@testable import NotchCore

@Suite("Island state machine")
struct IslandStateMachineTests {
    private func machine(_ behavior: IslandBehavior = IslandBehavior()) -> IslandStateMachine {
        IslandStateMachine(behavior: behavior)
    }

    @Test func startsCollapsed() {
        #expect(machine().state == .collapsed)
    }

    @Test func activityMovesRestingStateToPeek() {
        var m = machine()
        m.handle(.activityAvailabilityChanged(true))
        #expect(m.state == .peek)
        m.handle(.activityAvailabilityChanged(false))
        #expect(m.state == .collapsed)
    }

    @Test func hoverWaitsForIntentBeforeExpanding() {
        var m = machine()
        let effects = m.handle(.pointerEntered)
        #expect(m.state == .collapsed)
        #expect(effects.contains(.startTimer(.hoverIntent, seconds: 0.15)))

        m.handle(.timerFired(.hoverIntent))
        #expect(m.state == .expanded)
    }

    @Test func hoverIntentIgnoredIfPointerLeftFirst() {
        var m = machine()
        m.handle(.pointerEntered)
        let effects = m.handle(.pointerExited)
        #expect(effects.contains(.cancelTimer(.hoverIntent)))
        m.handle(.timerFired(.hoverIntent)) // stale timer
        #expect(m.state == .collapsed)
    }

    @Test func zeroHoverDelayExpandsImmediately() {
        var m = machine(IslandBehavior(hoverIntentDelay: 0))
        m.handle(.pointerEntered)
        #expect(m.state == .expanded)
    }

    @Test func hoverDisabledDoesNotExpand() {
        var m = machine(IslandBehavior(expandsOnHover: false))
        let effects = m.handle(.pointerEntered)
        #expect(!effects.contains(.startTimer(.hoverIntent, seconds: 0.15)))
        #expect(m.state == .collapsed)
    }

    @Test func expandedCollapsesAfterGraceWhenPointerLeaves() {
        var m = machine(IslandBehavior(hoverIntentDelay: 0))
        m.handle(.activityAvailabilityChanged(true))
        m.handle(.pointerEntered)
        let effects = m.handle(.pointerExited)
        #expect(effects.contains(.startTimer(.collapseGrace, seconds: 0.4)))
        #expect(m.state == .expanded)

        m.handle(.timerFired(.collapseGrace))
        #expect(m.state == .peek) // back to resting, which has an activity
    }

    @Test func reenteringCancelsCollapse() {
        var m = machine(IslandBehavior(hoverIntentDelay: 0))
        m.handle(.pointerEntered)
        m.handle(.pointerExited)
        let effects = m.handle(.pointerEntered)
        #expect(effects.contains(.cancelTimer(.collapseGrace)))
        m.handle(.timerFired(.collapseGrace)) // stale
        #expect(m.state == .expanded)
    }

    @Test func clickExpands() {
        var m = machine()
        m.handle(.clicked)
        #expect(m.state == .expanded)
    }

    @Test func panelDoesNotAutoCollapse() {
        var m = machine()
        m.handle(.shortcut(.togglePanel))
        #expect(m.state == .panel)
        let effects = m.handle(.pointerExited)
        #expect(!effects.contains { if case .startTimer(.collapseGrace, _) = $0 { true } else { false } })
        m.handle(.timerFired(.collapseGrace))
        #expect(m.state == .panel)
    }

    @Test func escapeAndClickOutsideClose() {
        var m = machine()
        m.handle(.shortcut(.togglePanel))
        m.handle(.escapePressed)
        #expect(m.state == .collapsed)

        m.handle(.clicked)
        m.handle(.clickedOutside)
        #expect(m.state == .collapsed)
    }

    @Test func swipeWalksThroughStates() {
        var m = machine()
        m.handle(.swipedDown)
        #expect(m.state == .expanded)
        m.handle(.swipedDown)
        #expect(m.state == .panel)
        m.handle(.swipedUp)
        #expect(m.state == .expanded)
        m.handle(.swipedUp)
        #expect(m.state == .collapsed)
    }

    @Test func swipesIgnoredWhenDisabled() {
        var m = machine(IslandBehavior(swipeGesturesEnabled: false))
        m.handle(.swipedDown)
        #expect(m.state == .collapsed)
    }

    @Test func shortcutsToggle() {
        var m = machine()
        m.handle(.shortcut(.toggleExpanded))
        #expect(m.state == .expanded)
        m.handle(.shortcut(.toggleExpanded))
        #expect(m.state == .collapsed)
        m.handle(.shortcut(.togglePanel))
        #expect(m.state == .panel)
        m.handle(.shortcut(.togglePanel))
        #expect(m.state == .collapsed)
    }

    @Test func dragOpensShelfAndHoldsItOpen() {
        var m = machine()
        m.handle(.dragEntered)
        #expect(m.state == .expanded)
        #expect(m.isDragging)

        // Pointer leaves mid-drag: no collapse scheduled while dragging.
        let exitEffects = m.handle(.pointerExited)
        #expect(!exitEffects.contains { if case .startTimer(.collapseGrace, _) = $0 { true } else { false } })
        m.handle(.timerFired(.collapseGrace))
        #expect(m.state == .expanded)

        let dropEffects = m.handle(.dropCompleted)
        #expect(dropEffects.contains(.startTimer(.collapseGrace, seconds: 0.4)))
    }

    @Test func suppressionHidesAndRestores() {
        var m = machine()
        m.handle(.activityAvailabilityChanged(true))
        m.handle(.shortcut(.togglePanel))
        m.handle(.suppressionChanged(true))
        #expect(m.state == .hidden)

        // Input is ignored while hidden.
        m.handle(.clicked)
        m.handle(.pointerEntered)
        m.handle(.dragEntered)
        #expect(m.state == .hidden)

        // Activity changes while hidden do not unhide.
        m.handle(.activityAvailabilityChanged(true))
        #expect(m.state == .hidden)

        m.handle(.suppressionChanged(false))
        #expect(m.state == .peek)
    }

    @Test func attentionPeekShowsAndSettles() {
        var m = machine()
        m.handle(.activityAvailabilityChanged(true))
        let effects = m.handle(.activityRequestedAttention)
        #expect(m.isAttentionPeek)
        #expect(effects.contains(.startTimer(.peekSettle, seconds: 2.5)))
        m.handle(.timerFired(.peekSettle))
        #expect(!m.isAttentionPeek)
        #expect(m.state == .peek)
    }

    @Test func attentionPeekDoesNotInterruptOpenIsland() {
        var m = machine()
        m.handle(.activityAvailabilityChanged(true))
        m.handle(.clicked)
        m.handle(.activityRequestedAttention)
        #expect(m.state == .expanded)
        #expect(!m.isAttentionPeek)
    }

    @Test func losingActivityWhileOpenKeepsIslandOpen() {
        var m = machine()
        m.handle(.activityAvailabilityChanged(true))
        m.handle(.clicked)
        m.handle(.activityAvailabilityChanged(false))
        #expect(m.state == .expanded)
        m.handle(.escapePressed)
        #expect(m.state == .collapsed)
    }

    /// Fuzz: no sequence of events may leave the machine in an inconsistent state.
    @Test func randomEventSequencesKeepInvariants() {
        let events: [IslandEvent] = [
            .pointerEntered, .pointerExited, .clicked, .swipedDown, .swipedUp,
            .shortcut(.toggleExpanded), .shortcut(.togglePanel), .escapePressed, .clickedOutside,
            .dragEntered, .dragExited, .dropCompleted,
            .activityAvailabilityChanged(true), .activityAvailabilityChanged(false),
            .activityRequestedAttention, .suppressionChanged(true), .suppressionChanged(false),
            .timerFired(.hoverIntent), .timerFired(.collapseGrace), .timerFired(.peekSettle),
        ]
        var generator = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<200 {
            var m = machine()
            for _ in 0..<60 {
                let event = events[Int(generator.next() % UInt64(events.count))]
                m.handle(event)
                #expect((m.state == .hidden) == m.isSuppressed)
                if m.isSuppressed {
                    #expect(!m.isPointerInside && !m.isDragging)
                }
                if !m.state.isOpen && !m.isSuppressed {
                    #expect(m.state == m.restingState)
                }
                if m.isAttentionPeek { #expect(m.state == .peek) }
            }
        }
    }
}

/// Small deterministic PRNG so the fuzz test is reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
