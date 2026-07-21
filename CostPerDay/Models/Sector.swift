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
        case .electronics: "Electronics"
        case .home: "Home & Furniture"
        case .appliances: "Appliances & Kitchen"
        case .personal: "Clothing & Personal"
        case .active: "Transport, Sport & Hobby"
        case .other: "Other"
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
