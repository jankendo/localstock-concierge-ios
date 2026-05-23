import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case shopping
    case inventory
    case receipt
    case concierge
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "ホーム"
        case .shopping:
            return "買い物"
        case .inventory:
            return "在庫"
        case .receipt:
            return "レシート"
        case .concierge:
            return "相談"
        case .settings:
            return "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .shopping:
            return "cart"
        case .inventory:
            return "shippingbox"
        case .receipt:
            return "doc.text.viewfinder"
        case .concierge:
            return "sparkles"
        case .settings:
            return "gearshape"
        }
    }
}
