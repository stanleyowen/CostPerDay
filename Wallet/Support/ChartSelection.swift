import SwiftUI
import Charts
import Observation

/// Chart scrubbing without redrawing the chart on every finger movement.
///
/// `chartXSelection` reports a raw value on every touch
/// move. Bound straight to `@State`, each report re-runs the owning view's body,
/// which rebuilds every mark and anything else that body derives. A `ScrubState`
/// snaps the raw value (to a data point, a day, …) and publishes only when the
/// snapped value changes. Views that read `value` (a readout, an indicator layer)
/// update; an `Equatable` plot that never reads it is left alone.
@MainActor @Observable
final class ScrubState<Value: Equatable> {
    private(set) var value: Value?
    /// The last raw value, echoed back to the chart. Not observed: it changes on
    /// every touch move.
    @ObservationIgnored private var raw: Any?

    func binding<Raw>(snap: @escaping (Raw) -> Value?) -> Binding<Raw?> {
        Binding(
            get: { self.raw as? Raw },
            set: { newRaw in
                self.raw = newRaw
                let snapped = newRaw.flatMap(snap)
                if snapped != self.value { self.value = snapped }
            }
        )
    }
}

extension View {
    /// Turns a single tap on a donut into the angle value under the finger, in the
    /// chart's own units (a running total from 12 o'clock, clockwise), so the caller
    /// can look up the slice. `chartAngleSelection` is a drag gesture, which inside a
    /// scroll view only fires after a press-and-hold; a tap fires straight away and
    /// leaves scrolling alone. Taps in the hole or outside the ring are ignored.
    func onDonutTap(total: Double, innerRatio: Double, perform action: @escaping (Double) -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame,
                              let angle = donutAngle(at: location, in: geo[frame], total: total, innerRatio: innerRatio)
                        else { return }
                        action(angle)
                    }
            }
        }
    }
}

/// The angle value (a running total from 12 o'clock, clockwise) at `point` on a
/// donut drawn in `rect`, or nil when the point is in the hole or outside the ring.
nonisolated func donutAngle(at point: CGPoint, in rect: CGRect, total: Double, innerRatio: Double) -> Double? {
    guard total > 0 else { return nil }
    let dx = point.x - rect.midX, dy = point.y - rect.midY
    let radius = (dx * dx + dy * dy).squareRoot()
    let outer = min(rect.width, rect.height) / 2
    guard radius >= outer * innerRatio * 0.8, radius <= outer * 1.08 else { return nil }
    var turn = atan2(dx, -dy) / (2 * .pi)
    if turn < 0 { turn += 1 }
    return turn * total
}

extension Array {
    /// Binary search over a sorted array: the index of the element whose key is
    /// nearest `target`.
    func nearestIndex(to target: Double, by key: (Element) -> Double) -> Int? {
        guard !isEmpty else { return nil }
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if key(self[mid]) < target { low = mid + 1 } else { high = mid }
        }
        if low > 0, abs(key(self[low - 1]) - target) <= abs(key(self[low]) - target) { return low - 1 }
        return low
    }
}
