import SwiftUI
import SwiftData

/// A category the user defined themselves, for anything the built-in list doesn't cover.
@Model
final class CustomCategory {
    var uuid: UUID = UUID()
    var name: String = ""
    var symbolName: String = "shippingbox"
    var sectorRaw: String = Sector.other.rawValue
    var tintRaw: String = CategoryTint.gray.rawValue
    var defaultLifetimeMonths: Int = 36
    var createdAt: Date = Date()

    init(
        name: String = "",
        symbolName: String = "shippingbox",
        sector: Sector = .other,
        tint: CategoryTint = .gray,
        defaultLifetimeMonths: Int = 36
    ) {
        self.uuid = UUID()
        self.name = name
        self.symbolName = symbolName
        self.sectorRaw = sector.rawValue
        self.tintRaw = tint.rawValue
        self.defaultLifetimeMonths = defaultLifetimeMonths
        self.createdAt = Date()
    }

    var sector: Sector {
        get { Sector(rawValue: sectorRaw) ?? .other }
        set { sectorRaw = newValue.rawValue }
    }

    var tint: CategoryTint {
        get { CategoryTint(rawValue: tintRaw) ?? .gray }
        set { tintRaw = newValue.rawValue }
    }

    /// The string stored on an item that points back at this category. Prefixed so it
    /// can never collide with a built-in `ItemCategory` raw value.
    var key: String { CustomCategory.keyPrefix + uuid.uuidString }

    static let keyPrefix = "custom:"

    static func uuid(fromKey key: String) -> UUID? {
        guard key.hasPrefix(keyPrefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(keyPrefix.count)))
    }
}

/// A fixed palette for custom categories — a named token rather than a raw colour so
/// it survives round-tripping through storage and backups.
enum CategoryTint: String, CaseIterable, Identifiable, Codable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, cyan, brown, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .gray: .gray
        }
    }

    var label: String {
        switch self {
        case .blue: String(localized: "Blue", comment: "Colour name")
        case .indigo: String(localized: "Indigo", comment: "Colour name")
        case .purple: String(localized: "Purple", comment: "Colour name")
        case .pink: String(localized: "Pink", comment: "Colour name")
        case .red: String(localized: "Red", comment: "Colour name")
        case .orange: String(localized: "Orange", comment: "Colour name")
        case .yellow: String(localized: "Yellow", comment: "Colour name")
        case .green: String(localized: "Green", comment: "Colour name")
        case .teal: String(localized: "Teal", comment: "Colour name")
        case .cyan: String(localized: "Cyan", comment: "Colour name")
        case .brown: String(localized: "Brown", comment: "Colour name")
        case .gray: String(localized: "Gray", comment: "Colour name")
        }
    }
}

/// SF Symbols offered when creating a custom category. Kept deliberately small and
/// concrete — a full symbol browser would be its own feature.
enum CategorySymbols {
    static let choices: [String] = [
        "shippingbox", "star", "heart", "house", "bed.double", "sofa",
        "table.furniture", "cabinet", "lightbulb", "paintpalette",
        "washer", "microwave", "frying.pan", "fork.knife", "cup.and.saucer",
        "tshirt", "shoe", "suitcase", "sparkles", "eyeglasses", "handbag",
        "bicycle", "car", "scooter", "dumbbell", "tent", "guitars", "dice",
        "wrench.and.screwdriver", "hammer", "leaf", "pawprint", "book",
        "gift", "cart", "camera", "headphones", "gamecontroller",
    ]
}
