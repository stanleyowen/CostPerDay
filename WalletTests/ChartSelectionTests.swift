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

    @Test func donutTapMapsToTheAngleUnderTheFinger() throws {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200) // centre (100, 100), radius 100
        func angle(_ x: Double, _ y: Double) -> Double? {
            donutAngle(at: CGPoint(x: x, y: y), in: rect, total: 400, innerRatio: 0.6)
        }
        // Clockwise from 12 o'clock, on the ring (radius 80).
        #expect(try abs(#require(angle(100.001, 20)) - 0) < 0.01)
        #expect(try abs(#require(angle(180, 100)) - 100) < 0.01)
        #expect(try abs(#require(angle(100, 180)) - 200) < 0.01)
        #expect(try abs(#require(angle(20, 100)) - 300) < 0.01)
        // The hole and outside the ring don't count.
        #expect(angle(100, 100) == nil)
        #expect(angle(130, 100) == nil)
        #expect(angle(100, -20) == nil)
        // Nothing to hit in an empty chart.
        #expect(donutAngle(at: CGPoint(x: 180, y: 100), in: rect, total: 0, innerRatio: 0.6) == nil)
    }
}
