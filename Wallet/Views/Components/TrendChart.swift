import SwiftUI
import Charts

/// One point on a `TrendChart`.
struct TrendPoint: Hashable {
    let date: Date
    let value: Double
}

/// A balance-style line with a soft fill, scaled to the data rather than to zero —
/// a NT$3,000 month on a NT$340,000 balance should still visibly move.
///
/// Drag across it to scrub: the selection snaps to the nearest point, and `readout`
/// (drawn above the plot) gets that point, or `nil` when nothing is selected. The
/// marks live in an `Equatable` plot that scrubbing never touches; only the readout
/// and a thin indicator layer update, and only when the snapped point changes.
struct TrendChart<Readout: View>: View {
    typealias Point = TrendPoint

    let points: [Point]
    var tint: Color
    var lineColors: [Color]
    var currency: String?
    var plotHeight: CGFloat
    var spacing: CGFloat
    @ViewBuilder var readout: (Point?) -> Readout

    @State private var scrub = ScrubState<Point>()

    init(series: [(date: Date, value: Double)], tint: Color = Brand.accent, lineColors: [Color] = [Brand.accent, Brand.highlight],
         currency: String? = nil, plotHeight: CGFloat, spacing: CGFloat = 12,
         @ViewBuilder readout: @escaping (Point?) -> Readout) {
        let points = series.map { Point(date: $0.date, value: $0.value) }
        self.points = points.isSorted { $0.date <= $1.date } ? points : points.sorted { $0.date < $1.date }
        self.tint = tint
        self.lineColors = lineColors
        self.currency = currency
        self.plotHeight = plotHeight
        self.spacing = spacing
        self.readout = readout
    }

    var body: some View {
        let points = self.points
        VStack(alignment: .leading, spacing: spacing) {
            readout(scrub.value)
            TrendPlot(points: points, tint: tint, lineColors: lineColors, currency: currency, scrub: scrub)
                .equatable()
                .frame(height: plotHeight)
                .sensitive()
        }
        .sensoryFeedback(.selection, trigger: scrub.value?.date)
    }
}

private extension Array {
    func isSorted(by inOrder: (Element, Element) -> Bool) -> Bool {
        zip(self, dropFirst()).allSatisfy { inOrder($0, $1) }
    }
}

/// The marks. Equatable on everything they draw, so a scrub (which changes only the
/// `ScrubState` this holds by reference) never re-evaluates them.
private struct TrendPlot: View, Equatable {
    typealias Point = TrendPoint

    let points: [Point]
    let tint: Color
    let lineColors: [Color]
    let currency: String?
    let scrub: ScrubState<Point>

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.points == rhs.points && lhs.tint == rhs.tint && lhs.lineColors == rhs.lineColors
            && lhs.currency == rhs.currency && lhs.scrub === rhs.scrub
    }

    /// Dates on the x-axis at the grain the range calls for: days for a month or
    /// two, months up to a little over a year, then years.
    private var dateFormat: Date.FormatStyle {
        guard let first = points.first?.date, let last = points.last?.date else { return .dateTime.day().month(.abbreviated) }
        let days = last.timeIntervalSince(first) / 86_400
        if days <= 62 { return .dateTime.day().month(.abbreviated) }
        if days <= 400 { return .dateTime.month(.abbreviated) }
        return .dateTime.year()
    }

    var body: some View {
        let values = points.map(\.value)
        let dateFormat = self.dateFormat
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.15, abs(high) * 0.002, 1)
        let floor = low - pad
        let points = self.points
        let line = LinearGradient(colors: lineColors, startPoint: .leading, endPoint: .trailing)

        Chart {
            ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Floor", floor), yEnd: .value("Balance", point.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.value))
                    .foregroundStyle(line)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: floor...(high + pad))
        .chartXSelection(value: scrub.binding { (date: Date) in
            points.nearestIndex(to: date.timeIntervalSinceReferenceDate) { $0.date.timeIntervalSinceReferenceDate }.map { points[$0] }
        })
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisTick(length: 4).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(date, format: dateFormat).font(.caption2) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self), let currency { Text(Money.compact(v, code: currency)).font(.caption2) }
                }
            }
        }
        .chartOverlay { proxy in
            ScrubIndicator(proxy: proxy, scrub: scrub, tint: tint)
        }
    }
}

/// The rule and dot under the finger. Reads the scrub state itself, so it's the only
/// part of the chart that redraws while scrubbing.
private struct ScrubIndicator: View {
    let proxy: ChartProxy
    let scrub: ScrubState<TrendPoint>
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            if let point = scrub.value, let frame = proxy.plotFrame,
               let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.value) {
                let plot = geo[frame]
                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 1, height: plot.height)
                    .position(x: plot.minX + x, y: plot.midY)
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .position(x: plot.minX + x, y: plot.minY + y)
            }
        }
        .allowsHitTesting(false)
    }
}
