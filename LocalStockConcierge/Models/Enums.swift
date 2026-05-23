import Foundation
import SwiftUI

enum ProductCategory: String, Codable, CaseIterable, Identifiable {
    case dailyGoods
    case laundry
    case bath
    case kitchen
    case food
    case medicine
    case storage
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyGoods:
            return "日用品"
        case .laundry:
            return "洗濯"
        case .bath:
            return "浴室"
        case .kitchen:
            return "キッチン"
        case .food:
            return "食品"
        case .medicine:
            return "薬"
        case .storage:
            return "収納"
        case .other:
            return "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyGoods:
            return "house.fill"
        case .laundry:
            return "washer.fill"
        case .bath:
            return "shower.fill"
        case .kitchen:
            return "fork.knife"
        case .food:
            return "carrot.fill"
        case .medicine:
            return "cross.case.fill"
        case .storage:
            return "archivebox.fill"
        case .other:
            return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .dailyGoods:
            return StockTheme.coral
        case .laundry:
            return StockTheme.mint
        case .bath:
            return StockTheme.sky
        case .kitchen:
            return StockTheme.lemon
        case .food:
            return .green
        case .medicine:
            return .red
        case .storage:
            return .purple
        case .other:
            return .secondary
        }
    }
}

enum ManagementType: String, Codable, CaseIterable, Identifiable {
    case unopenedPackage
    case cyclePrediction
    case expiry
    case manual
    case wishOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unopenedPackage:
            return "開封型"
        case .cyclePrediction:
            return "周期予測"
        case .expiry:
            return "期限管理"
        case .manual:
            return "手動"
        case .wishOnly:
            return "欲しいもの"
        }
    }
}

enum InventoryEventType: String, Codable, CaseIterable {
    case purchased
    case opened
    case consumed
    case manualCorrection
    case addedToShopping
    case shoppingCompleted
    case expired
    case checked

    var label: String {
        switch self {
        case .purchased:
            return "購入"
        case .opened:
            return "開封"
        case .consumed:
            return "消費"
        case .manualCorrection:
            return "補正"
        case .addedToShopping:
            return "買い物追加"
        case .shoppingCompleted:
            return "購入済み"
        case .expired:
            return "期限切れ"
        case .checked:
            return "確認"
        }
    }
}

enum EventSource: String, Codable, CaseIterable {
    case manual
    case ocrReceipt
    case llmToolCall
    case nfc
    case prediction
    case system

    var label: String {
        switch self {
        case .manual:
            return "手動"
        case .ocrReceipt:
            return "OCR"
        case .llmToolCall:
            return "AI"
        case .nfc:
            return "NFC"
        case .prediction:
            return "予測"
        case .system:
            return "システム"
        }
    }
}

enum InventoryStatus: String, Codable, CaseIterable {
    case ok
    case buySoon
    case buyNow
    case check
    case unknown

    var label: String {
        switch self {
        case .ok:
            return "十分"
        case .buySoon:
            return "そろそろ"
        case .buyNow:
            return "今買う"
        case .check:
            return "確認"
        case .unknown:
            return "不明"
        }
    }

    var tint: Color {
        switch self {
        case .ok:
            return .green
        case .buySoon:
            return .orange
        case .buyNow:
            return .red
        case .check:
            return .blue
        case .unknown:
            return .secondary
        }
    }
}

enum StoreType: String, Codable, CaseIterable, Identifiable {
    case any
    case supermarket
    case drugstore
    case homeCenter
    case online

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any:
            return "指定なし"
        case .supermarket:
            return "スーパー"
        case .drugstore:
            return "ドラッグストア"
        case .homeCenter:
            return "ホームセンター"
        case .online:
            return "オンライン"
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        case .urgent:
            return "至急"
        }
    }
}

enum ShoppingStatus: String, Codable, CaseIterable {
    case active
    case completed
    case skipped
}

enum WishStatus: String, Codable, CaseIterable {
    case active
    case purchased
    case archived
}

extension String {
    var normalizedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .lowercased()
    }
}
