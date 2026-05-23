import Foundation
import SwiftData

@Model
final class Product {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var category: ProductCategory
    var locationName: String
    var unit: String
    var managementType: ManagementType
    var minStock: Double
    var idealStock: Double
    var cycleDays: Int?
    var leadDays: Int?
    var barcode: String?
    var aliases: [String]
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String? = nil,
        category: ProductCategory,
        locationName: String,
        unit: String,
        managementType: ManagementType,
        minStock: Double,
        idealStock: Double,
        cycleDays: Int? = nil,
        leadDays: Int? = nil,
        barcode: String? = nil,
        aliases: [String] = [],
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? name.normalizedForSearch
        self.category = category
        self.locationName = locationName
        self.unit = unit
        self.managementType = managementType
        self.minStock = minStock
        self.idealStock = idealStock
        self.cycleDays = cycleDays
        self.leadDays = leadDays
        self.barcode = barcode
        self.aliases = aliases
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class InventoryEvent {
    @Attribute(.unique) var id: UUID
    var productId: UUID
    var type: InventoryEventType
    var quantity: Double
    var source: EventSource
    var note: String?
    var confidence: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        productId: UUID,
        type: InventoryEventType,
        quantity: Double,
        source: EventSource,
        note: String? = nil,
        confidence: Double = 1,
        createdAt: Date = .now
    ) {
        self.id = id
        self.productId = productId
        self.type = type
        self.quantity = quantity
        self.source = source
        self.note = note
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

@Model
final class InventoryState {
    @Attribute(.unique) var productId: UUID
    var estimatedStock: Double
    var status: InventoryStatus
    var confidence: Double
    var lastPurchasedAt: Date?
    var lastOpenedAt: Date?
    var predictedRunoutAt: Date?
    var updatedAt: Date

    init(
        productId: UUID,
        estimatedStock: Double,
        status: InventoryStatus,
        confidence: Double,
        lastPurchasedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        predictedRunoutAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.productId = productId
        self.estimatedStock = estimatedStock
        self.status = status
        self.confidence = confidence
        self.lastPurchasedAt = lastPurchasedAt
        self.lastOpenedAt = lastOpenedAt
        self.predictedRunoutAt = predictedRunoutAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ShoppingItem {
    @Attribute(.unique) var id: UUID
    var productId: UUID?
    var name: String
    var quantity: Double?
    var unit: String?
    var storeType: StoreType
    var priority: Priority
    var reason: String
    var status: ShoppingStatus
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        productId: UUID? = nil,
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        storeType: StoreType = .any,
        priority: Priority = .medium,
        reason: String,
        status: ShoppingStatus = .active,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.storeType = storeType
        self.priority = priority
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

@Model
final class WishItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var url: String?
    var price: Int?
    var priority: Priority
    var status: WishStatus
    var memo: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        url: String? = nil,
        price: Int? = nil,
        priority: Priority = .medium,
        status: WishStatus = .active,
        memo: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.price = price
        self.priority = priority
        self.status = status
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Receipt {
    @Attribute(.unique) var id: UUID
    var rawText: String
    var storeName: String?
    var purchasedAt: Date?
    var totalAmount: Int?
    var parsedJSON: String?
    var imageLocalPath: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        rawText: String,
        storeName: String? = nil,
        purchasedAt: Date? = nil,
        totalAmount: Int? = nil,
        parsedJSON: String? = nil,
        imageLocalPath: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rawText = rawText
        self.storeName = storeName
        self.purchasedAt = purchasedAt
        self.totalAmount = totalAmount
        self.parsedJSON = parsedJSON
        self.imageLocalPath = imageLocalPath
        self.createdAt = createdAt
    }
}

@Model
final class AppPreference {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date

    init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
