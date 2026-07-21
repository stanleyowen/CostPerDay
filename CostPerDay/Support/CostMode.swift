import Foundation

/// Which of the two cost-per-day readings the interface is currently showing.
enum CostMode: String, CaseIterable, Identifiable {
    /// price ÷ days actually owned — decreases for as long as the item is retained.
    case actual
    /// price ÷ expected lifetime — the figure budgeted at the time of purchase.
    case planned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .actual: String(localized: "To date", comment: "Cost basis: cost per day so far")
        case .planned: String(localized: "Planned", comment: "Cost basis: cost per day as budgeted")
        }
    }

    var explanation: String {
        switch self {
        case .actual:
            String(
                localized: "The purchase price divided by the number of days owned. This figure decreases for as long as the item is retained.",
                comment: "Explanation of the 'To date' cost basis"
            )
        case .planned:
            String(
                localized: "The purchase price divided by the expected lifetime. This is the amount each day was budgeted to cost.",
                comment: "Explanation of the 'Planned' cost basis"
            )
        }
    }
}
