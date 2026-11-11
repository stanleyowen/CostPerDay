import SwiftUI
import Charts

/// A balance-style line with a soft fill, scaled to the data rather than to zero —
/// a NT$3,000 month on a NT$340,000 balance should still visibly move.
struct TrendChart: View {
    struct Point: Hashable {
        let date: Date
        let value: Double
    }

    let points: [Point]
    var tint: Color = Brand.amber
    var lineStyle: AnyShapeStyle = AnyShapeStyle(Brand.flame)
    var currency: String?
    var showsAxis = true
    @Binding var selection: Date?

    init(series: [(date: Date, value: Double)], tint: Color = Brand.amber, lineStyle: AnyShapeStyle = AnyShapeStyle(Brand.flame),
         currency: String? = nil, showsAxis: Bool = true, selection: Binding<Date?> = .constant(nil)) {
        self.points = series.map { Point(date: $0.date, value: $0.value) }
        self.tint = tint
        self.lineStyle = lineStyle
        self.currency = currency
        self.showsAxis = showsAxis
        self._selection = selection
    }

    /// The point nearest the current selection.
    var focused: Point? {
        selection.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    }

    var body: some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.15, abs(high) * 0.002, 1)
        let floor = low - pad
        let focused = focused

        Chart {
            ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Floor", floor), yEnd: .value("Balance", point.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.value))
                    .foregroundStyle(lineStyle)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let focused {
                RuleMark(x: .value("Date", focused.date)).foregroundStyle(.secondary.opacity(0.4))
                PointMark(x: .value("Date", focused.date), y: .value("Balance", focused.value)).foregroundStyle(tint)
            }
        }
        .chartYScale(domain: floor...(high + pad))
        .chartXSelection(value: $selection)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let v = value.as(Double.self), let currency { Text(Money.compact(v, code: currency)).font(.caption2) }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: focused?.date)
    }
}
