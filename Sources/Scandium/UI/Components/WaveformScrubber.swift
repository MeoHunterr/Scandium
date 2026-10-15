// WaveformScrubber.swift — Custom waveform-bar scrubber using GeometryReader
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Renders SoundCloud waveform sample data as vertical bars in a horizontally-stretched
// view. The played portion is highlighted; the user can drag to scrub through the track.
// Compatible with iOS 15 (no Canvas — uses GeometryReader + HStack of rounded rects).

import SwiftUI

struct WaveformScrubber: View {
    let samples: [Float]
    @Binding var progress: Double
    let bufferedProgress: Double
    let onSeek: (Double) -> Void

    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0

    init(
        samples: [Float],
        progress: Binding<Double>,
        bufferedProgress: Double,
        onSeek: @escaping (Double) -> Void
    ) {
        self.samples = samples
        self._progress = progress
        self.bufferedProgress = bufferedProgress
        self.onSeek = onSeek
    }

    private let barSpacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 2
    private let playedColor = Color.white
    private let unplayedColor = Color.white.opacity(0.18)
    private let bufferedColor = Color.white.opacity(0.10)
    private let barCornerRadius: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let totalHeight = geometry.size.height
            let displaySamples = downsample(to: totalWidth)
            let barWidth = max(1.5, (totalWidth - barSpacing * CGFloat(displaySamples.count - 1)) / CGFloat(displaySamples.count))
            let activeProgress = isDragging ? dragProgress : progress

            ZStack(alignment: .leading) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(displaySamples.enumerated()), id: \.offset) { index, sample in
                        let normalizedHeight = max(minBarHeight, CGFloat(sample) * totalHeight)
                        let barFraction = Double(index) / Double(max(1, displaySamples.count - 1))

                        RoundedRectangle(cornerRadius: barCornerRadius)
                            .fill(barColor(for: barFraction, activeProgress: activeProgress))
                            .frame(width: barWidth, height: normalizedHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if isDragging {
                    scrubberIndicator(totalHeight: totalHeight, totalWidth: totalWidth, progress: dragProgress)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, Double(value.location.x / totalWidth)))
                        isDragging = true
                        dragProgress = fraction
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, Double(value.location.x / totalWidth)))
                        isDragging = false
                        dragProgress = fraction
                        onSeek(fraction)
                    }
            )
        }
    }

    // MARK: - Bar Color

    private func barColor(for barFraction: Double, activeProgress: Double) -> Color {
        if barFraction <= activeProgress {
            return playedColor
        } else if barFraction <= bufferedProgress {
            return bufferedColor
        } else {
            return unplayedColor
        }
    }

    // MARK: - Scrubber Indicator

    private func scrubberIndicator(totalHeight: CGFloat, totalWidth: CGFloat, progress: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 3, height: totalHeight + 8)
            .shadow(color: .white.opacity(0.4), radius: 4, x: 0, y: 0)
            .offset(x: CGFloat(progress) * totalWidth - 1.5)
            .animation(.interactiveSpring(), value: progress)
    }

    // MARK: - Downsample

    private func downsample(to width: CGFloat) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0.3, count: max(1, Int(width / 4)))
        }

        let targetCount = max(1, Int(width / (barSpacing + 3)))

        guard samples.count > targetCount else {
            return normalizedSamples(samples)
        }

        let chunkSize = Double(samples.count) / Double(targetCount)
        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let start = Int(Double(i) * chunkSize)
            let end = min(Int(Double(i + 1) * chunkSize), samples.count)
            guard start < end else {
                result.append(0)
                continue
            }
            let chunk = samples[start..<end]
            let avg = chunk.reduce(0, +) / Float(chunk.count)
            result.append(avg)
        }

        return normalizedSamples(result)
    }

    private func normalizedSamples(_ input: [Float]) -> [Float] {
        guard let maxVal = input.max(), maxVal > 0 else {
            return input.map { _ in 0.1 }
        }
        return input.map { max(0.05, $0 / maxVal) }
    }
}

// MARK: - Simple Progress Scrubber (Fallback without waveform data)

struct SimpleProgressScrubber: View {
    @Binding var progress: Double
    let bufferedProgress: Double
    let onSeek: (Double) -> Void

    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0

    init(
        progress: Binding<Double>,
        bufferedProgress: Double,
        onSeek: @escaping (Double) -> Void
    ) {
        self._progress = progress
        self.bufferedProgress = bufferedProgress
        self.onSeek = onSeek
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let activeProgress = isDragging ? dragProgress : progress

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: CGFloat(bufferedProgress) * totalWidth, height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: CGFloat(activeProgress) * totalWidth, height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                    .shadow(color: .white.opacity(0.3), radius: 4)
                    .offset(x: CGFloat(activeProgress) * totalWidth - (isDragging ? 8 : 5))
                    .animation(.interactiveSpring(), value: isDragging)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, Double(value.location.x / totalWidth)))
                        isDragging = true
                        dragProgress = fraction
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, Double(value.location.x / totalWidth)))
                        isDragging = false
                        onSeek(fraction)
                    }
            )
        }
        .frame(height: 30)
    }
}
