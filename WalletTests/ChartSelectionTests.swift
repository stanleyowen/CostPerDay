import Testing
import Foundation
import Observation
@testable import Wallet

@MainActor
struct ChartSelectionTests {
    @Test func nearestIndexPicksTheClosestKey() {
        let keys: [Double] = [0, 10, 20, 30]
        #expect(keys.nearestIndex(to: -5) { $0 } == 0)
        #expect(keys.nearestIndex(to: 4) { $0 } == 0)
        #expect(keys.nearestIndex(to: 6) { $0 } == 1)
        #expect(keys.nearestIndex(to: 15) { $0 } == 1) // a tie goes to the earlier point
        #expect(keys.nearestIndex(to: 29) { $0 } == 3)
        #expect(keys.nearestIndex(to: 99) { $0 } == 3)
        #expect([Double]().nearestIndex(to: 1) { $0 } == nil)
    }

    @Test func scrubPublishesOnlyWhenTheSnappedValueChanges() {
        let scrub = ScrubState<Int>()
        let binding = scrub.binding { (raw: Double) in Int(raw / 10) }
        var changes = 0
        func observe() {
            withObservationTracking { _ = scrub.value } onChange: { changes += 1 }
        }

        observe()
        binding.wrappedValue = 1     // snaps to 0: a change from nil
        #expect(scrub.value == 0)
        #expect(changes == 1)

        observe()
        binding.wrappedValue = 4     // still 0
        binding.wrappedValue = 9.5   // still 0
        #expect(changes == 1)
        #expect(binding.wrappedValue == 9.5) // the raw value echoes back to the chart

        binding.wrappedValue = 12    // now 1
        #expect(scrub.value == 1)
        #expect(changes == 2)

        observe()
        binding.wrappedValue = nil   // gesture ended
        #expect(scrub.value == nil)
        #expect(changes == 3)
    }

    @Test func sinkForwardsEveryValue() {
        let sink = SelectionSink<Double>()
        var seen: [Double?] = []
        let binding = sink.binding { seen.append($0) }
        binding.wrappedValue = 10
        binding.wrappedValue = 11
        binding.wrappedValue = nil
        #expect(seen == [10, 11, nil])
    }
}
