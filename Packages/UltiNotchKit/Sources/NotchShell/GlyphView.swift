import NotchModuleKit
import SwiftUI

extension Tint {
    var color: Color {
        switch self {
        case .primary: Color.white
        case .secondary: Color.white.opacity(0.6)
        case .accent: Color.accentColor
        case .positive: Color.green
        case .warning: Color.orange
        case .critical: Color.red
        }
    }
}

/// Renders a module's declarative compact content.
struct GlyphView: View {
    let glyph: Glyph

    var body: some View {
        switch glyph {
        case .none:
            Color.clear
        case .symbol(let name, let tint):
            Image(systemName: name).foregroundStyle(tint.color)
        case .text(let text, let tint):
            Text(text).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(tint.color)
        case .progress(let fraction, let tint):
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: fraction)
                    .stroke(tint.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        case .level(let fraction, let tint):
            Capsule().fill(Color.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint.color).frame(width: 50 * max(0, min(1, fraction)))
                }
                .frame(width: 50, height: 6)
        case .artwork:
            // ponytail: placeholder until the artwork cache lands with the MediaRemote bridge.
            Image(systemName: "music.note").foregroundStyle(Color.white)
        case .equalizer(let isPlaying):
            EqualizerView(isPlaying: isPlaying)
        case .countdown(let date, let tint):
            Text(date, style: .timer).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(tint.color)
        }
    }
}

/// Decorative bars, not real audio levels (that needs a screen-audio permission).
/// Ticks 4 times a second only while playing.
struct EqualizerView: View {
    let isPlaying: Bool

    var body: some View {
        if isPlaying {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                bars(at: context.date)
                    .animation(.easeInOut(duration: 0.25), value: context.date)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at date: Date?) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(Color.white).frame(width: 3, height: Self.height(i, date))
            }
        }
        .frame(height: 14)
    }

    static func height(_ i: Int, _ date: Date?) -> CGFloat {
        guard let date else { return 3 }
        let t = date.timeIntervalSinceReferenceDate * 2.3 + Double(i) * 1.7
        return 4 + 10 * abs(sin(t))
    }
}
