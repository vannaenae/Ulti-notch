import NotchModuleKit
import Observation
import SwiftUI

/// Per-display presentation state.
@MainActor
@Observable
final class IslandModel {
    var state: IslandState = .collapsed
    var display: DisplayGeometry
    var pageIndex = 0
    let layout = IslandLayout()

    init(display: DisplayGeometry) { self.display = display }

    var notch: NotchShape { NotchGeometry.notch(on: display, layout: layout) }
    var windowFrame: CGRect { NotchGeometry.windowFrame(on: display, layout: layout) }
    var islandFrame: CGRect { NotchGeometry.islandFrame(for: state, on: display, layout: layout) }
}

struct IslandView: View {
    let model: IslandModel
    let content: IslandContent
    let onTap: () -> Void

    var body: some View {
        let window = model.windowFrame
        let frame = model.islandFrame
        ZStack(alignment: .topLeading) {
            if model.state != .hidden {
                island(size: frame.size)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX - window.minX, y: window.maxY - frame.maxY)
            }
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.state)
    }

    private func island(size: CGSize) -> some View {
        let isVirtual = model.notch.kind == .virtual
        let radius: CGFloat = model.state.isOpen ? 22 : (isVirtual ? size.height / 2 : 10)
        let top: CGFloat = isVirtual ? radius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: top,
            style: .continuous
        )
        return ZStack(alignment: .top) {
            shape.fill(Color.black)
            stateContent(model.state)
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func stateContent(_ state: IslandState) -> some View {
        switch state {
        case .hidden, .collapsed:
            EmptyView()
        case .peek:
            if let primary = content.resolution.primary {
                HStack(spacing: 0) {
                    GlyphView(glyph: primary.content.leading).frame(width: CGFloat(model.layout.peekWingWidth))
                    Spacer(minLength: 0)
                    GlyphView(glyph: primary.content.trailing).frame(width: CGFloat(model.layout.peekWingWidth))
                }
                .frame(height: model.notch.rect.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(primary.content.accessibilityLabel)
            }
        case .expanded, .panel:
            expanded
        }
    }

    private var expanded: some View {
        let pages = content.pages
        let index = pages.isEmpty ? 0 : min(model.pageIndex, pages.count - 1)
        return VStack(spacing: 10) {
            Spacer().frame(height: model.notch.rect.height)
            if pages.isEmpty {
                Text("Nothing here yet. Turn on modules in Settings.").foregroundStyle(.secondary)
            } else {
                pages[index].view.frame(maxWidth: .infinity, maxHeight: .infinity)
                if pages.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(pages.indices, id: \.self) { i in
                            Circle().fill(Color.white.opacity(i == index ? 0.9 : 0.3)).frame(width: 6, height: 6)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .foregroundStyle(Color.white)
        .transition(.opacity)
    }
}
