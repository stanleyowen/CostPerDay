import SwiftUI

enum GadgetCategory: String, CaseIterable, Identifiable, Codable {
    case phone, laptop, tablet, desktop, monitor, audio, wearable
    case camera, gaming, accessory, smartHome, other

    var id: String { rawValue }

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
        case .accessory: "Accessory"
        case .smartHome: "Smart Home"
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
        case .accessory: "cable.connector"
        case .smartHome: "homekit"
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
        case .accessory: 24
        case .smartHome: 48
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
        case .accessory: .gray
        case .smartHome: .yellow
        case .other: .secondary
        }
    }
}
