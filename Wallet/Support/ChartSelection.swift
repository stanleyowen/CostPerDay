import SwiftUI
import Observation

/// Chart scrubbing without redrawing the chart on every finger movement.
///
/// `chartXSelection` and `chartAngleSelection` report a raw value on every touch
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

/// An event-only selection binding for charts whose raw selection nothing displays
/// (the donuts map an angle to a slice): every change calls `onChange`, but storing
/// it never invalidates a view.
@MainActor
final class SelectionSink<Raw> {
    @ObservationIgnored private var raw: Raw?

    func binding(_ onChange: @escaping (Raw?) -> Void) -> Binding<Raw?> {
        Binding(
            get: { self.raw },
            set: { newRaw in
                self.raw = newRaw
                onChange(newRaw)
            }
        )
    }
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
