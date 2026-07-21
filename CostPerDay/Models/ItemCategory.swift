import SwiftUI

/// The built-in categories. Raw values are persisted on every item, so existing
/// cases must never be renamed — only added to.
enum ItemCategory: String, CaseIterable, Identifiable, Codable {
    // Electronics
    case phone, laptop, tablet, desktop, monitor, audio, wearable
    case camera, gaming, smartHome, accessory
    // Home & furniture
    case bed, seating, tableDesk, storage, lighting, decor
    // Appliances & kitchen
    case largeAppliance, smallAppliance, cookware, tableware
    // Clothing & personal
    case clothing, footwear, bag, jewellery, eyewear
    // Transport, sport & hobby
    case bicycle, vehicle, sports, outdoor, instrument, games
    // Other
    case tools, other

    var id: String { rawValue }

    var sector: Sector {
        switch self {
        case .phone, .laptop, .tablet, .desktop, .monitor, .audio,
             .wearable, .camera, .gaming, .smartHome, .accessory:
            .electronics
        case .bed, .seating, .tableDesk, .storage, .lighting, .decor:
            .home
        case .largeAppliance, .smallAppliance, .cookware, .tableware:
            .appliances
        case .clothing, .footwear, .bag, .jewellery, .eyewear:
            .personal
        case .bicycle, .vehicle, .sports, .outdoor, .instrument, .games:
            .active
        case .tools, .other:
            .other
        }
    }

    var label: String {
        switch self {
        case .phone: "Phone"
        case .laptop: "Laptop"
        case .tablet: "Tablet"
        case .desktop: "Desktop"
        case .monitor: "Monitor"
        case .audio: "Audio"
        case .wearable: "Wearable"
        case .camera: "Camera"
        case .gaming: "Gaming"
        case .smartHome: "Smart Home"
        case .accessory: "Accessory"
        case .bed: "Bed & Mattress"
        case .seating: "Sofa & Seating"
        case .tableDesk: "Table & Desk"
        case .storage: "Storage"
        case .lighting: "Lighting"
        case .decor: "Decor & Textiles"
        case .largeAppliance: "Large Appliance"
        case .smallAppliance: "Small Appliance"
        case .cookware: "Cookware"
        case .tableware: "Tableware"
        case .clothing: "Clothing"
        case .footwear: "Footwear"
        case .bag: "Bags & Luggage"
        case .jewellery: "Jewellery"
        case .eyewear: "Eyewear"
        case .bicycle: "Bicycle"
        case .vehicle: "Vehicle"
        case .sports: "Sports & Fitness"
        case .outdoor: "Outdoor Gear"
        case .instrument: "Instrument"
        case .games: "Games & Toys"
        case .tools: "Tools & DIY"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .phone: "iphone"
        case .laptop: "laptopcomputer"
        case .tablet: "ipad"
        case .desktop: "desktopcomputer"
        case .monitor: "display"
        case .audio: "headphones"
        case .wearable: "applewatch"
        case .camera: "camera"
        case .gaming: "gamecontroller"
        case .smartHome: "homekit"
        case .accessory: "cable.connector"
        case .bed: "bed.double"
        case .seating: "sofa"
        case .tableDesk: "table.furniture"
        case .storage: "cabinet"
        case .lighting: "lightbulb"
        case .decor: "paintpalette"
        case .largeAppliance: "washer"
        case .smallAppliance: "microwave"
        case .cookware: "frying.pan"
        case .tableware: "fork.knife"
        case .clothing: "tshirt"
        case .footwear: "shoe"
        case .bag: "suitcase"
        case .jewellery: "sparkles"
        case .eyewear: "eyeglasses"
        case .bicycle: "bicycle"
        case .vehicle: "car"
        case .sports: "dumbbell"
        case .outdoor: "tent"
        case .instrument: "guitars"
        case .games: "dice"
        case .tools: "wrench.and.screwdriver"
        case .other: "shippingbox"
        }
    }

    /// A sane starting point for expected lifetime, in months. Only a default —
    /// the user can always override it per item.
    var defaultLifetimeMonths: Int {
        switch self {
        case .phone: 36
        case .laptop: 60
        case .tablet: 60
        case .desktop: 72
        case .monitor: 84
        case .audio: 48
        case .wearable: 36
        case .camera: 72
        case .gaming: 60
        case .smartHome: 48
        case .accessory: 24
        case .bed: 96
        case .seating: 120
        case .tableDesk: 120
        case .storage: 120
        case .lighting: 84
        case .decor: 60
        case .largeAppliance: 120
        case .smallAppliance: 60
        case .cookware: 84
        case .tableware: 60
        case .clothing: 36
        case .footwear: 24
        case .bag: 60
        case .jewellery: 180
        case .eyewear: 24
        case .bicycle: 84
        case .vehicle: 120
        case .sports: 48
        case .outdoor: 84
        case .instrument: 180
        case .games: 60
        case .tools: 120
        case .other: 36
        }
    }

    var tint: Color {
        switch self {
        case .phone: .blue
        case .laptop: .indigo
        case .tablet: .teal
        case .desktop: .purple
        case .monitor: .cyan
        case .audio: .pink
        case .wearable: .orange
        case .camera: .brown
        case .gaming: .green
        case .smartHome: .yellow
        case .accessory: .gray
        case .bed: .indigo
        case .seating: .brown
        case .tableDesk: .orange
        case .storage: .gray
        case .lighting: .yellow
        case .decor: .pink
        case .largeAppliance: .teal
        case .smallAppliance: .cyan
        case .cookware: .red
        case .tableware: .orange
        case .clothing: .pink
        case .footwear: .brown
        case .bag: .purple
        case .jewellery: .yellow
        case .eyewear: .blue
        case .bicycle: .green
        case .vehicle: .red
        case .sports: .orange
        case .outdoor: .green
        case .instrument: .purple
        case .games: .cyan
        case .tools: .gray
        case .other: .secondary
        }
    }

    static func inSector(_ sector: Sector) -> [ItemCategory] {
        allCases.filter { $0.sector == sector }
    }
}
