import SwiftUI

final class ThemeManager: ObservableObject {
    @AppStorage("appColorScheme") var selection: Int = 0   // 0 system, 1 light, 2 dark
    @AppStorage("pureBlack") var pureBlack: Bool = true

    var colorScheme: ColorScheme? {
        switch selection {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var bgColor: Color {
        (colorScheme == .dark && pureBlack) ? .black : Color(.systemBackground)
    }

    var cardColor: Color {
        (colorScheme == .dark && pureBlack) ? Color(white: 0.12) : Color(.systemGray6)
    }

    var label: String {
        switch selection {
        case 1: return "Light"
        case 2: return "Dark"
        default: return "System"
        }
    }
}
