import SwiftUI

// Palette lifted from the PWA (Tailwind theme in frontend/src/app.css).
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let brand = Color(hex: 0xDD4B33)        // brand-600 / coral accent
    static let brandLight = Color(hex: 0xFDF4F2)   // brand-50
    static let brandDark = Color(hex: 0x45150D)    // brand-950

    static let overdue = Color(hex: 0xEF4444)      // red-500
    static let dueToday = Color(hex: 0x10B981)     // emerald-500
    static let upcomingAccent = Color(hex: 0xA78BFA) // violet-400
    static let deadlineFlag = Color(hex: 0xD97706) // amber-600
}

struct AppAccent: Identifiable, Equatable, Sendable {
    let name: String
    let label: String
    let color: Color

    var id: String { name }
}

enum AppAccentPalette {
    static let storageKey = "toodue-accent"
    static let defaultName = "sky"

    static let options: [AppAccent] = [
        AppAccent(name: "sky", label: "Sky", color: Color(hex: 0x0EA5E9)),
        AppAccent(name: "coral", label: "Coral", color: Color.brand),
        AppAccent(name: "emerald", label: "Emerald", color: Color(hex: 0x10B981)),
        AppAccent(name: "violet", label: "Violet", color: Color(hex: 0x8B5CF6)),
        AppAccent(name: "amber", label: "Amber", color: Color(hex: 0xF59E0B)),
        AppAccent(name: "rose", label: "Rose", color: Color(hex: 0xF43F5E)),
    ]

    static func color(for name: String) -> Color {
        options.first { $0.name == name }?.color ?? color(for: defaultName)
    }

    static func normalized(_ name: String) -> String {
        options.contains { $0.name == name } ? name : defaultName
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .p1: Color(hex: 0xDC2626) // red-600
        case .p2: Color(hex: 0xF97316) // orange-500
        case .p3: Color(hex: 0x3B82F6) // blue-500
        case .p4: Color(hex: 0xA1A5AB) // zinc-400
        }
    }
}

// Project colors mirror the PWA's named Tailwind swatches.
enum ProjectColor {
    static let named: [(name: String, color: Color)] = [
        ("slate", Color(hex: 0x64748B)),
        ("red", Color(hex: 0xEF4444)),
        ("orange", Color(hex: 0xF97316)),
        ("amber", Color(hex: 0xF59E0B)),
        ("emerald", Color(hex: 0x10B981)),
        ("teal", Color(hex: 0x14B8A6)),
        ("sky", Color(hex: 0x0EA5E9)),
        ("blue", Color(hex: 0x3B82F6)),
        ("violet", Color(hex: 0x8B5CF6)),
        ("fuchsia", Color(hex: 0xD946EF)),
        ("pink", Color(hex: 0xEC4899)),
        ("rose", Color(hex: 0xF43F5E)),
    ]

    static func color(for name: String) -> Color {
        named.first { $0.name == name }?.color ?? named[0].color
    }
}
