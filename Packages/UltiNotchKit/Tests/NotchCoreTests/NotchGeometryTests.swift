import Foundation
import Testing
@testable import NotchCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Display metrics below are illustrative round numbers, not measurements of a
/// specific Mac. Real values get recorded in docs/testing once we run on hardware.
@Suite("Notch geometry")
struct NotchGeometryTests {
    /// Built-in display with a 200pt notch, 32pt tall.
    let notched = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1500, height: 1000),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 650,
        auxiliaryTopRightWidth: 650
    )

    /// External display placed to the right of the built-in one.
    let external = DisplayGeometry(frame: CGRect(x: 1500, y: 0, width: 2560, height: 1440))

    @Test func detectsHardwareNotch() {
        let shape = NotchGeometry.notch(on: notched)
        #expect(shape.kind == .hardware)
        #expect(shape.rect == CGRect(x: 650, y: 968, width: 200, height: 32))
    }

    @Test func fallsBackToVirtualIslandWithoutNotch() {
        let layout = IslandLayout()
        let shape = NotchGeometry.notch(on: external, layout: layout)
        #expect(shape.kind == .virtual)
        #expect(shape.rect.midX == external.frame.midX)
        #expect(shape.rect.maxY == external.frame.maxY - CGFloat(layout.virtualTopMargin))
        #expect(shape.rect.width == CGFloat(layout.virtualNotchWidth))
    }

    @Test func safeAreaWithoutAuxiliaryAreasIsNotANotch() {
        let odd = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1500, height: 1000), safeAreaTop: 32)
        #expect(NotchGeometry.notch(on: odd).kind == .virtual)
    }

    @Test func tuningAdjustsSizeAndOffsetButKeepsTopEdge() {
        let tuning = NotchTuning(widthAdjustment: 10, heightAdjustment: 2, horizontalOffset: -5)
        let rect = NotchGeometry.notch(on: notched, tuning: tuning).rect
        #expect(rect.width == 210)
        #expect(rect.height == 34)
        #expect(rect.midX == 745)
        #expect(rect.maxY == 1000)
    }

    @Test func statesGrowDownwardsFromTheNotchCentre() {
        let notch = NotchGeometry.notch(on: notched).rect
        var previousArea: CGFloat = 0
        for state in [IslandState.collapsed, .peek, .expanded, .panel] {
            let frame = NotchGeometry.islandFrame(for: state, on: notched)
            #expect(frame.maxY == notch.maxY, "top edge pinned for \(state)")
            #expect(frame.midX == notch.midX, "centred for \(state)")
            let area = frame.width * frame.height
            #expect(area > previousArea, "\(state) larger than the previous state")
            previousArea = area
        }
    }

    @Test func islandIsClampedOnScreen() {
        let tuning = NotchTuning(horizontalOffset: -2000)
        let frame = NotchGeometry.islandFrame(for: .panel, on: notched, tuning: tuning)
        #expect(frame.minX == notched.frame.minX)
    }

    @Test func islandNeverWiderThanScreen() {
        let tiny = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let frame = NotchGeometry.islandFrame(for: .panel, on: tiny)
        #expect(frame.width == 600)
        #expect(frame.minX == 0)
    }

    @Test func windowFrameContainsEveryState() {
        for display in [notched, external] {
            let window = NotchGeometry.windowFrame(on: display)
            for state in IslandState.allCases {
                #expect(window.contains(NotchGeometry.islandFrame(for: state, on: display)))
            }
            #expect(display.frame.contains(window))
        }
    }

    @Test func externalDisplayUsesItsOwnOrigin() {
        let frame = NotchGeometry.islandFrame(for: .expanded, on: external)
        #expect(frame.minX > external.frame.minX)
        #expect(frame.maxY == external.frame.maxY - 6)
    }
}
