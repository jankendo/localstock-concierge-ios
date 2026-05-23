import Foundation

enum InventoryCalculator {
    static func state(for product: Product, events: [InventoryEvent], now: Date = .now) -> InventoryStateSnapshot {
        let purchased = events.filter { $0.type == .purchased }.reduce(0) { $0 + $1.quantity }
        let opened = events.filter { $0.type == .opened }.reduce(0) { $0 + $1.quantity }
        let corrections = events.filter { $0.type == .manualCorrection }.reduce(0) { $0 + $1.quantity }
        let estimated = purchased - opened + corrections

        let lastPurchased = events.first(where: { $0.type == .purchased })?.createdAt
        let lastOpened = events.first(where: { $0.type == .opened })?.createdAt
        let lastEvent = events.first?.createdAt

        let predictedRunout: Date?
        if let cycleDays = product.cycleDays, let anchor = lastPurchased ?? lastOpened {
            predictedRunout = Calendar.current.date(byAdding: .day, value: cycleDays, to: anchor)
        } else {
            predictedRunout = nil
        }

        let status: InventoryStatus
        switch product.managementType {
        case .unopenedPackage:
            if estimated <= 0 {
                status = .buyNow
            } else if estimated <= product.minStock {
                status = .buySoon
            } else if let lastEvent, Calendar.current.dateComponents([.day], from: lastEvent, to: now).day ?? 0 >= 60 {
                status = .check
            } else {
                status = .ok
            }
        case .cyclePrediction:
            if let predictedRunout, predictedRunout <= now {
                status = .buySoon
            } else if lastPurchased == nil {
                status = .unknown
            } else {
                status = .ok
            }
        case .expiry:
            status = predictedRunout.map { $0 <= now ? .buySoon : .ok } ?? .check
        case .manual:
            status = lastEvent == nil ? .unknown : .check
        case .wishOnly:
            status = .unknown
        }

        let confidence: Double
        if events.isEmpty {
            confidence = 0.3
        } else if status == .check || status == .unknown {
            confidence = 0.55
        } else {
            confidence = min(1, max(0.55, events.map(\.confidence).reduce(0, +) / Double(events.count)))
        }

        return InventoryStateSnapshot(
            productId: product.id,
            estimatedStock: estimated,
            status: status,
            confidence: confidence,
            lastPurchasedAt: lastPurchased,
            lastOpenedAt: lastOpened,
            predictedRunoutAt: predictedRunout
        )
    }

    static func alerts(products: [Product], events: [InventoryEvent]) -> [InventoryAlert] {
        products.compactMap { product in
            let productEvents = events.filter { $0.productId == product.id }
            let state = state(for: product, events: productEvents)
            guard state.status == .buyNow || state.status == .buySoon || state.status == .check else { return nil }
            return InventoryAlert(product: product, state: state)
        }
        .sorted { lhs, rhs in
            lhs.state.status.sortRank < rhs.state.status.sortRank
        }
    }
}

struct InventoryStateSnapshot: Identifiable, Hashable {
    var id: UUID { productId }
    var productId: UUID
    var estimatedStock: Double
    var status: InventoryStatus
    var confidence: Double
    var lastPurchasedAt: Date?
    var lastOpenedAt: Date?
    var predictedRunoutAt: Date?
}

struct InventoryAlert: Identifiable {
    var id: UUID { product.id }
    let product: Product
    let state: InventoryStateSnapshot

    var reason: String {
        switch state.status {
        case .buyNow:
            return "予備が\(state.estimatedStock.formattedStock)\(product.unit)"
        case .buySoon:
            return "最低在庫 \(product.minStock.formattedStock)\(product.unit) に近い"
        case .check:
            return "最近確認していない"
        case .ok, .unknown:
            return "確認が必要"
        }
    }
}

private extension InventoryStatus {
    var sortRank: Int {
        switch self {
        case .buyNow:
            return 0
        case .buySoon:
            return 1
        case .check:
            return 2
        case .unknown:
            return 3
        case .ok:
            return 4
        }
    }
}
