import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

struct Palette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    var accent: Color { dark ? Color(red: 0.94, green: 0.61, blue: 0.72) : Color(red: 0.60, green: 0.22, blue: 0.36) }
    var background: Color { dark ? Color(red: 0.09, green: 0.07, blue: 0.09) : Color(red: 0.98, green: 0.95, blue: 0.95) }
    var surface: Color { dark ? Color(red: 0.16, green: 0.12, blue: 0.15) : .white }
    var sidebar: Color { dark ? Color(red: 0.12, green: 0.08, blue: 0.11) : Color(red: 0.96, green: 0.88, blue: 0.90) }
    var selected: Color { dark ? Color(red: 0.25, green: 0.16, blue: 0.21) : .white }
    var text: Color { dark ? Color(red: 0.96, green: 0.91, blue: 0.93) : Color(red: 0.22, green: 0.15, blue: 0.19) }
}
