import SwiftUI

/// Launch-argument hooks for driving the simulator from scripts (screenshots, manual
/// QA against an imported export). Every flag is inert in release builds.
enum DebugFlags {
    /// `-scrollAnchor top|center|bottom`: where long scrolling screens start.
    static var scrollAnchor: UnitPoint? {
        #if DEBUG
        switch value(after: "-scrollAnchor") {
        case "center": return .center
        case "bottom": return .bottom
        default: return nil
        }
        #else
        return nil
        #endif
    }

    static func value(after flag: String) -> String? {
        #if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    static func has(_ flag: String) -> Bool {
        #if DEBUG
        return CommandLine.arguments.contains(flag)
        #else
        return false
        #endif
    }
}
