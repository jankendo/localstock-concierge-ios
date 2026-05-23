import Foundation
import SwiftData

@MainActor
protocol InventoryRepository {
    func products() throws -> [Product]
    func activeProducts() throws -> [Product]
    func product(id: UUID) throws -> Product?
    func searchProducts(query: String) throws -> [Product]
    func createProduct(_ draft: ProductDraft) throws -> Product
    func recordPurchase(productId: UUID, quantity: Double, unit: String?, source: EventSource, confidence: Double, note: String?) throws -> InventoryEvent
    func recordOpened(productId: UUID, quantity: Double, source: EventSource, note: String?) throws -> InventoryEvent
    func correctInventory(productId: UUID, estimatedStock: Double, reason: String) throws -> InventoryEvent
    func addShoppingItem(productId: UUID?, name: String, quantity: Double?, unit: String?, storeType: StoreType, priority: Priority, reason: String) throws -> ShoppingItem
    func completeShoppingItem(id: UUID) throws
    func activeShoppingItems() throws -> [ShoppingItem]
    func events(for productId: UUID) throws -> [InventoryEvent]
    func allEvents() throws -> [InventoryEvent]
    func saveReceipt(rawText: String, parsedJSON: String?, storeName: String?, purchasedAt: Date?, totalAmount: Int?, imageLocalPath: String?) throws -> Receipt
}

struct ProductDraft {
    var name: String
    var category: ProductCategory
    var locationName: String
    var unit: String
    var managementType: ManagementType
    var minStock: Double
    var idealStock: Double
    var cycleDays: Int?
    var aliases: [String]
}

@MainActor
final class SwiftDataInventoryRepository: InventoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func products() throws -> [Product] {
        try context.fetch(FetchDescriptor<Product>(sortBy: [SortDescriptor(\.name)]))
    }

    func activeProducts() throws -> [Product] {
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func product(id: UUID) throws -> Product? {
        var descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func searchProducts(query: String) throws -> [Product] {
        let normalized = query.normalizedForSearch
        guard !normalized.isEmpty else { return try activeProducts() }

        return try activeProducts().filter { product in
            product.normalizedName.contains(normalized)
                || product.aliases.map(\.normalizedForSearch).contains { $0.contains(normalized) || normalized.contains($0) }
        }
    }

    func createProduct(_ draft: ProductDraft) throws -> Product {
        let product = Product(
            name: draft.name,
            category: draft.category,
            locationName: draft.locationName,
            unit: draft.unit,
            managementType: draft.managementType,
            minStock: draft.minStock,
            idealStock: draft.idealStock,
            cycleDays: draft.cycleDays,
            aliases: draft.aliases
        )
        context.insert(product)
        try context.save()
        return product
    }

    func recordPurchase(productId: UUID, quantity: Double, unit: String?, source: EventSource, confidence: Double, note: String?) throws -> InventoryEvent {
        let event = InventoryEvent(
            productId: productId,
            type: .purchased,
            quantity: max(quantity, 0),
            source: source,
            note: unit.map { "unit=\($0)" }.joinedNote(with: note),
            confidence: confidence
        )
        context.insert(event)
        try autoAddShoppingIfNeeded(productId: productId)
        try context.save()
        return event
    }

    func recordOpened(productId: UUID, quantity: Double, source: EventSource, note: String?) throws -> InventoryEvent {
        let event = InventoryEvent(
            productId: productId,
            type: .opened,
            quantity: max(quantity, 0),
            source: source,
            note: note,
            confidence: 1
        )
        context.insert(event)
        try autoAddShoppingIfNeeded(productId: productId)
        try context.save()
        return event
    }

    func correctInventory(productId: UUID, estimatedStock: Double, reason: String) throws -> InventoryEvent {
        let current = try InventoryCalculator.state(
            for: try requireProduct(productId),
            events: events(for: productId)
        )
        let delta = estimatedStock - current.estimatedStock
        let event = InventoryEvent(
            productId: productId,
            type: .manualCorrection,
            quantity: delta,
            source: .manual,
            note: reason,
            confidence: 1
        )
        context.insert(event)
        try autoAddShoppingIfNeeded(productId: productId)
        try context.save()
        return event
    }

    func addShoppingItem(productId: UUID?, name: String, quantity: Double?, unit: String?, storeType: StoreType, priority: Priority, reason: String) throws -> ShoppingItem {
        if let existing = try activeShoppingItems().first(where: { item in
            if let productId, item.productId == productId { return true }
            return item.name.normalizedForSearch == name.normalizedForSearch
        }) {
            existing.quantity = max(existing.quantity ?? 0, quantity ?? existing.quantity ?? 1)
            existing.priority = priority
            existing.reason = reason
            try context.save()
            return existing
        }

        let item = ShoppingItem(
            productId: productId,
            name: name,
            quantity: quantity,
            unit: unit,
            storeType: storeType,
            priority: priority,
            reason: reason
        )
        context.insert(item)
        if let productId {
            context.insert(InventoryEvent(productId: productId, type: .addedToShopping, quantity: quantity ?? 1, source: .system, note: reason))
        }
        try context.save()
        return item
    }

    func completeShoppingItem(id: UUID) throws {
        var descriptor = FetchDescriptor<ShoppingItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let item = try context.fetch(descriptor).first else { return }
        item.status = .completed
        item.completedAt = .now
        if let productId = item.productId {
            context.insert(InventoryEvent(productId: productId, type: .shoppingCompleted, quantity: item.quantity ?? 1, source: .manual, note: item.name))
        }
        try context.save()
    }

    func activeShoppingItems() throws -> [ShoppingItem] {
        let descriptor = FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor).filter { $0.status == .active }.sorted { lhs, rhs in
            if lhs.priority.rank == rhs.priority.rank {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.priority.rank > rhs.priority.rank
        }
    }

    func events(for productId: UUID) throws -> [InventoryEvent] {
        let descriptor = FetchDescriptor<InventoryEvent>(
            predicate: #Predicate { $0.productId == productId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func allEvents() throws -> [InventoryEvent] {
        try context.fetch(FetchDescriptor<InventoryEvent>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func saveReceipt(rawText: String, parsedJSON: String?, storeName: String?, purchasedAt: Date?, totalAmount: Int?, imageLocalPath: String?) throws -> Receipt {
        let receipt = Receipt(
            rawText: rawText,
            storeName: storeName,
            purchasedAt: purchasedAt,
            totalAmount: totalAmount,
            parsedJSON: parsedJSON,
            imageLocalPath: imageLocalPath
        )
        context.insert(receipt)
        try context.save()
        return receipt
    }

    private func requireProduct(_ id: UUID) throws -> Product {
        guard let product = try product(id: id) else {
            throw InventoryRepositoryError.productNotFound
        }
        return product
    }

    private func autoAddShoppingIfNeeded(productId: UUID) throws {
        let product = try requireProduct(productId)
        let state = try InventoryCalculator.state(for: product, events: events(for: productId))
        guard state.status == .buyNow || state.status == .buySoon else { return }

        _ = try addShoppingItem(
            productId: product.id,
            name: product.name,
            quantity: max(product.idealStock - state.estimatedStock, 1),
            unit: product.unit,
            storeType: product.category.defaultStoreType,
            priority: state.status == .buyNow ? .urgent : .high,
            reason: "\(state.status.label): 推定\(state.estimatedStock.formattedStock) \(product.unit)"
        )
    }
}

private extension Priority {
    var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        case .urgent:
            return 3
        }
    }
}

enum InventoryRepositoryError: LocalizedError {
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "商品が見つかりません。"
        }
    }
}

private extension Optional where Wrapped == String {
    func joinedNote(with other: String?) -> String? {
        [self, other].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
    }
}

extension ProductCategory {
    var defaultStoreType: StoreType {
        switch self {
        case .dailyGoods, .laundry, .bath, .medicine:
            return .drugstore
        case .kitchen, .food:
            return .supermarket
        case .storage:
            return .homeCenter
        case .other:
            return .any
        }
    }
}

extension Double {
    var formattedStock: String {
        if rounded(.towardZero) == self {
            return String(Int(self))
        }
        return String(format: "%.1f", self)
    }
}
