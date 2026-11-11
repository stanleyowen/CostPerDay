import SwiftUI

/// The broad area of life a category belongs to. Sectors keep the category picker
/// scannable now that the app covers everything you own, and give the dashboard a
/// coarser breakdown than per-category spending.
enum Sector: String, CaseIterable, Identifiable, Codable {
    case electronics
    case home
    case appliances
    case personal
    case active
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .electronics: String(localized: "Electronics", comment: "Sector name")
        case .home: String(localized: "Home & Furniture", comment: "Sector name")
        case .appliances: String(localized: "Appliances & Kitchen", comment: "Sector name")
        case .personal: String(localized: "Clothing & Personal", comment: "Sector name")
        case .active: String(localized: "Transport, Sport & Hobby", comment: "Sector name")
        case .other: String(localized: "Other", comment: "Sector name")
        }
    }

    var symbol: String {
        switch self {
        case .electronics: "laptopcomputer"
        case .home: "sofa"
        case .appliances: "washer"
        case .personal: "tshirt"
        case .active: "bicycle"
        case .other: "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .electronics: .blue
        case .home: .brown
        case .appliances: .teal
        case .personal: .pink
        case .active: .green
        case .other: .gray
        }
    }
}
