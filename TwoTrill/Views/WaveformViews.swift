import SwiftUI

/// Vertical bars, one per value, centered on the midline.
struct WaveformBars: View {
    let bars: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard !bars.isEmpty else { return }
            let step = size.width / CGFloat(bars.count)
            for (i, value) in bars.enumerated() {
                let height = max(2, CGFloat(value) * size.height)
                let rect = CGRect(x: CGFloat(i) * step, y: (size.height - height) / 2,
                                  width: max(1, step * 0.6), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
    }
}

/// The whole song's waveform with a draggable window marking the clip.
/// Drag the window to move it, or touch anywhere else to jump it there.
struct WaveformScrubber: View {
    let waveform: Waveform?
    let duration: Double
    let clipLength: Double
    @Binding var clipStart: Double
    var playhead: Double?
    var onDragEnded: () -> Void = {}

    @State private var dragOrigin: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let safeDuration = max(duration, 0.1)
            let length = min(clipLength, safeDuration)
            let bars = waveform?.bars(count: max(1, Int(width / 3)), from: 0, to: safeDuration) ?? []
            let windowX = width * clipStart / safeDuration
            let windowWidth = max(10, width * length / safeDuration)

            ZStack(alignment: .leading) {
                WaveformBars(bars: bars, color: .white.opacity(0.3))
                WaveformBars(bars: bars, color: .pink)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: windowWidth).offset(x: windowX)
                    }
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.pink.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink, lineWidth: 2))
                    .frame(width: windowWidth)
                    .offset(x: windowX)
                if let playhead {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2)
                        .offset(x: width * playhead / safeDuration)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil {
                            let touched = value.startLocation.x / width * safeDuration
                            let insideWindow = touched >= clipStart && touched <= clipStart + length
                            dragOrigin = insideWindow ? clipStart : touched - length / 2
                        }
                        let delta = value.translation.width / width * safeDuration
                        clipStart = min(max(0, (dragOrigin ?? 0) + delta), max(0, safeDuration - length))
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        onDragEnded()
                    }
            )
        }
    }
}

/// A close-up of just the clip, with bar lines and beat ticks so you can see where cuts can land.
struct ClipWaveform: View {
    let waveform: Waveform?
    let grid: BeatGrid?
    let start: Double
    let length: Double
    var playhead: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                WaveformBars(bars: waveform?.bars(count: max(1, Int(width / 3)), from: start, to: start + length) ?? [],
                             color: .pink.opacity(0.8))
                if let grid, length > 0 {
                    Canvas { context, size in
                        var k = Int(((start - grid.firstBeat) / grid.period).rounded(.up))
                        while grid.time(ofBeat: k) < start + length {
                            let x = (grid.time(ofBeat: k) - start) / length * size.width
                            let isBar = grid.isDownbeat(k)
                            let rect = CGRect(x: x, y: isBar ? 0 : size.height * 0.8,
                                              width: isBar ? 1.5 : 1, height: isBar ? size.height : size.height * 0.2)
                            context.fill(Path(rect), with: .color(.white.opacity(isBar ? 0.6 : 0.35)))
                            k += 1
                        }
                    }
                }
                if let playhead, playhead >= start, playhead <= start + length, length > 0 {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2, height: height)
                        .offset(x: width * (playhead - start) / length)
                }
            }
        }
    }
}
