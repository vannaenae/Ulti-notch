import AppKit
import NotchModuleKit
import SwiftUI

extension DisplayGeometry {
    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// One island on one display: panel, state machine, timers, input.
@MainActor
final class IslandController {
    private let panel: IslandPanel
    private let model: IslandModel
    private let content: IslandContent
    private var machine = IslandStateMachine()
    private var timers: [IslandTimer: Task<Void, Never>] = [:]
    private var monitors: [Any] = []
    private var isInside = false
    private var scroll = CGSize.zero
    private var scrollHandled = false

    init(screen: NSScreen, content: IslandContent) {
        self.content = content
        model = IslandModel(display: DisplayGeometry(screen))
        panel = IslandPanel(frame: model.windowFrame)

        let hosting = NSHostingView(rootView: IslandView(model: model, content: content) { [weak self] in
            self?.send(.clicked)
        })
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        installMonitors()
        resolutionChanged()
    }

    func update(screen: NSScreen) {
        model.display = DisplayGeometry(screen)
        panel.setFrame(model.windowFrame, display: true)
    }

    func resolutionChanged() {
        send(.activityAvailabilityChanged(content.resolution.primary != nil))
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        timers.values.forEach { $0.cancel() }
        timers = [:]
        panel.orderOut(nil)
    }

    // MARK: State machine

    private func send(_ event: IslandEvent) {
        for effect in machine.handle(event) {
            switch effect {
            case .startTimer(let timer, let seconds):
                timers[timer]?.cancel()
                timers[timer] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    self?.send(.timerFired(timer))
                }
            case .cancelTimer(let timer):
                timers[timer]?.cancel()
                timers[timer] = nil
            }
        }
        if model.state != machine.state {
            model.state = machine.state
            if !machine.state.isOpen { model.pageIndex = 0 }
        }
    }

    // MARK: Input

    private func installMonitors() {
        // Global monitors for mouse events need no permission. ponytail: wakes on every
        // mouse move (a rect check); idle cost is zero while the mouse is still.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.clickedOutside) }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel], handler: { [weak self] event in
            let isScroll = event.type == .scrollWheel
            let dx = event.scrollingDeltaX
            let dy = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
            let began = event.phase.contains(.began)
            MainActor.assumeIsolated {
                self?.pointerMoved()
                if isScroll { self?.scrolled(dx: dx, dy: dy, began: began) }
            }
            return event
        }) { monitors.append(m) }
    }

    private func pointerMoved() {
        let inside = model.islandFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        guard inside != isInside else { return }
        isInside = inside
        send(inside ? .pointerEntered : .pointerExited)
    }

    /// Two-finger swipes over the island. dy > 0 means fingers moved down.
    private func scrolled(dx: CGFloat, dy: CGFloat, began: Bool) {
        if began {
            scroll = .zero
            scrollHandled = false
        }
        guard !scrollHandled else { return }
        scroll.width += dx
        scroll.height += dy
        let threshold: CGFloat = 30
        if abs(scroll.height) > threshold, abs(scroll.height) > abs(scroll.width) {
            scrollHandled = true
            send(scroll.height > 0 ? .swipedDown : .swipedUp)
        } else if abs(scroll.width) > threshold, machine.state.isOpen, !content.pages.isEmpty {
            scrollHandled = true
            let step = scroll.width < 0 ? 1 : -1
            model.pageIndex = (model.pageIndex + step + content.pages.count) % content.pages.count
        }
    }
}
