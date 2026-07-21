import Foundation

/// Which of the two cost-per-day readings the UI is currently showing.
enum CostMode: String, CaseIterable, Identifiable {
    /// price ÷ days actually owned — falls every day you keep the thing.
    case actual
    /// price ÷ expected lifetime — what you budgeted for at purchase.
    case planned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .actual: "So far"
        case .planned: "Planned"
        }
    }

    var explanation: String {
        switch self {
        case .actual: "Price divided by the days you've actually owned it. Keeps dropping the longer you hold on."
        case .planned: "Price divided by the lifetime you expect. What each day was supposed to cost."
        }
    }
}
