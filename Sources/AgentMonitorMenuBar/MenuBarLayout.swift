import SwiftUI

enum MenuBarPanelSize: String, CaseIterable {
    case compact = "Compact"
    case standard = "Standard"
    case tall = "Tall"

    var height: CGFloat {
        switch self {
        case .compact: 420
        case .standard: 560
        case .tall: 720
        }
    }
}

enum MenuBarLayout {
    static let width: CGFloat = 420
}
