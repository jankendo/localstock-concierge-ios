import Foundation

struct LocalStockRemoteSnapshot {
    var products: [Product]
    var events: [InventoryEvent]
    var shoppingItems: [ShoppingItem]
    var wishItems: [WishItem]
    var receipts: [Receipt]
}

struct RemoteHouseholdRecord: Codable {
    let id: UUID
    let name: String
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case inviteCode = "invite_code"
    }
}

struct RemoteHouseholdMembership: Codable {
    let householdID: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case householdID = "household_id"
        case role
    }
}

struct RemoteHouseholdInsert: Encodable {
    let id: UUID
    let name: String
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdBy = "created_by"
    }
}

struct RemoteHouseholdMemberInsert: Encodable {
    let householdID: UUID
    let userID: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case householdID = "household_id"
        case userID = "user_id"
        case role
    }
}

struct RemoteJoinHouseholdParams: Encodable {
    let inviteCodeInput: String

    enum CodingKeys: String, CodingKey {
        case inviteCodeInput = "invite_code_input"
    }
}

struct RemoteProductRecord: Codable {
    let id: UUID
    let householdID: UUID
    let name: String
    let normalizedName: String
    let category: String
    let locationName: String
    let unit: String
    let managementType: String
    let minStock: Double
    let idealStock: Double
    let cycleDays: Int?
    let leadDays: Int?
    let barcode: String?
    let aliases: [String]
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name
        case normalizedName = "normalized_name"
        case category
        case locationName = "location_name"
        case unit
        case managementType = "management_type"
        case minStock = "min_stock"
        case idealStock = "ideal_stock"
        case cycleDays = "cycle_days"
        case leadDays = "lead_days"
        case barcode
        case aliases
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func domainProduct() -> Product {
        Product(
            id: id,
            name: name,
            normalizedName: normalizedName,
            category: ProductCategory(rawValue: category) ?? .other,
            locationName: locationName,
            unit: unit,
            managementType: ManagementType(rawValue: managementType) ?? .manual,
            minStock: minStock,
            idealStock: idealStock,
            cycleDays: cycleDays,
            leadDays: leadDays,
            barcode: barcode,
            aliases: aliases,
            isActive: isActive,
            createdAt: RemoteDate.parse(createdAt) ?? .now,
            updatedAt: RemoteDate.parse(updatedAt) ?? .now
        )
    }
}

struct RemoteProductPayload: Encodable {
    let id: UUID
    let householdID: UUID
    let name: String
    let normalizedName: String
    let category: String
    let locationName: String
    let unit: String
    let managementType: String
    let minStock: Double
    let idealStock: Double
    let cycleDays: Int?
    let leadDays: Int?
    let barcode: String?
    let aliases: [String]
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name
        case normalizedName = "normalized_name"
        case category
        case locationName = "location_name"
        case unit
        case managementType = "management_type"
        case minStock = "min_stock"
        case idealStock = "ideal_stock"
        case cycleDays = "cycle_days"
        case leadDays = "lead_days"
        case barcode
        case aliases
        case isActive = "is_active"
    }

    init(product: Product, householdID: UUID) {
        self.id = product.id
        self.householdID = householdID
        self.name = product.name
        self.normalizedName = product.normalizedName
        self.category = product.category.rawValue
        self.locationName = product.locationName
        self.unit = product.unit
        self.managementType = product.managementType.rawValue
        self.minStock = product.minStock
        self.idealStock = product.idealStock
        self.cycleDays = product.cycleDays
        self.leadDays = product.leadDays
        self.barcode = product.barcode
        self.aliases = product.aliases
        self.isActive = product.isActive
    }
}

struct RemoteInventoryEventRecord: Codable {
    let id: UUID
    let householdID: UUID
    let productID: UUID
    let type: String
    let quantity: Double
    let source: String
    let note: String?
    let confidence: Double
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case productID = "product_id"
        case type
        case quantity
        case source
        case note
        case confidence
        case createdAt = "created_at"
    }

    func domainEvent() -> InventoryEvent {
        InventoryEvent(
            id: id,
            productId: productID,
            type: InventoryEventType(rawValue: type) ?? .checked,
            quantity: quantity,
            source: EventSource(rawValue: source) ?? .system,
            note: note,
            confidence: confidence,
            createdAt: RemoteDate.parse(createdAt) ?? .now
        )
    }
}

struct RemoteInventoryEventPayload: Encodable {
    let id: UUID
    let householdID: UUID
    let productID: UUID
    let type: String
    let quantity: Double
    let source: String
    let note: String?
    let confidence: Double
    let createdBy: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case productID = "product_id"
        case type
        case quantity
        case source
        case note
        case confidence
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    init(event: InventoryEvent, householdID: UUID, userID: UUID) {
        self.id = event.id
        self.householdID = householdID
        self.productID = event.productId
        self.type = event.type.rawValue
        self.quantity = event.quantity
        self.source = event.source.rawValue
        self.note = event.note
        self.confidence = event.confidence
        self.createdBy = userID
        self.createdAt = RemoteDate.format(event.createdAt)
    }
}

struct RemoteShoppingItemRecord: Codable {
    let id: UUID
    let householdID: UUID
    let productID: UUID?
    let name: String
    let quantity: Double?
    let unit: String?
    let storeType: String
    let priority: String
    let reason: String
    let status: String
    let createdAt: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case productID = "product_id"
        case name
        case quantity
        case unit
        case storeType = "store_type"
        case priority
        case reason
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    func domainItem() -> ShoppingItem {
        ShoppingItem(
            id: id,
            productId: productID,
            name: name,
            quantity: quantity,
            unit: unit,
            storeType: StoreType(rawValue: storeType) ?? .any,
            priority: Priority(rawValue: priority) ?? .medium,
            reason: reason,
            status: ShoppingStatus(rawValue: status) ?? .active,
            createdAt: RemoteDate.parse(createdAt) ?? .now,
            completedAt: RemoteDate.parse(completedAt)
        )
    }
}

struct RemoteShoppingItemPayload: Encodable {
    let id: UUID
    let householdID: UUID
    let productID: UUID?
    let name: String
    let quantity: Double?
    let unit: String?
    let storeType: String
    let priority: String
    let reason: String
    let status: String
    let createdBy: UUID
    let createdAt: String
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case productID = "product_id"
        case name
        case quantity
        case unit
        case storeType = "store_type"
        case priority
        case reason
        case status
        case createdBy = "created_by"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    init(item: ShoppingItem, householdID: UUID, userID: UUID) {
        self.id = item.id
        self.householdID = householdID
        self.productID = item.productId
        self.name = item.name
        self.quantity = item.quantity
        self.unit = item.unit
        self.storeType = item.storeType.rawValue
        self.priority = item.priority.rawValue
        self.reason = item.reason
        self.status = item.status.rawValue
        self.createdBy = userID
        self.createdAt = RemoteDate.format(item.createdAt)
        self.completedAt = item.completedAt.map(RemoteDate.format)
    }
}

struct RemoteReceiptRecord: Codable {
    let id: UUID
    let householdID: UUID
    let rawText: String
    let storeName: String?
    let purchasedAt: String?
    let totalAmount: Int?
    let parsedJSON: String?
    let imageLocalPath: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case rawText = "raw_text"
        case storeName = "store_name"
        case purchasedAt = "purchased_at"
        case totalAmount = "total_amount"
        case parsedJSON = "parsed_json"
        case imageLocalPath = "image_local_path"
        case createdAt = "created_at"
    }

    func domainReceipt() -> Receipt {
        Receipt(
            id: id,
            rawText: rawText,
            storeName: storeName,
            purchasedAt: RemoteDate.parse(purchasedAt),
            totalAmount: totalAmount,
            parsedJSON: parsedJSON,
            imageLocalPath: imageLocalPath,
            createdAt: RemoteDate.parse(createdAt) ?? .now
        )
    }
}

struct RemoteReceiptPayload: Encodable {
    let id: UUID
    let householdID: UUID
    let rawText: String
    let storeName: String?
    let purchasedAt: String?
    let totalAmount: Int?
    let parsedJSON: String?
    let imageLocalPath: String?
    let createdBy: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case rawText = "raw_text"
        case storeName = "store_name"
        case purchasedAt = "purchased_at"
        case totalAmount = "total_amount"
        case parsedJSON = "parsed_json"
        case imageLocalPath = "image_local_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    init(receipt: Receipt, householdID: UUID, userID: UUID) {
        self.id = receipt.id
        self.householdID = householdID
        self.rawText = receipt.rawText
        self.storeName = receipt.storeName
        self.purchasedAt = receipt.purchasedAt.map(RemoteDate.format)
        self.totalAmount = receipt.totalAmount
        self.parsedJSON = receipt.parsedJSON
        self.imageLocalPath = receipt.imageLocalPath
        self.createdBy = userID
        self.createdAt = RemoteDate.format(receipt.createdAt)
    }
}

struct RemoteShoppingUpdate: Encodable {
    let status: String
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case completedAt = "completed_at"
    }
}

struct RemoteWishItemRecord: Codable {
    let id: UUID
    let householdID: UUID
    let name: String
    let url: String?
    let price: Int?
    let priority: String
    let status: String
    let memo: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name
        case url
        case price
        case priority
        case status
        case memo
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func domainItem() -> WishItem {
        WishItem(
            id: id,
            name: name,
            url: url,
            price: price,
            priority: Priority(rawValue: priority) ?? .medium,
            status: WishStatus(rawValue: status) ?? .active,
            memo: memo,
            createdAt: RemoteDate.parse(createdAt) ?? .now,
            updatedAt: RemoteDate.parse(updatedAt) ?? .now
        )
    }
}

struct RemoteWishItemPayload: Encodable {
    let id: UUID
    let householdID: UUID
    let name: String
    let url: String?
    let price: Int?
    let priority: String
    let status: String
    let memo: String?
    let createdBy: UUID
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name
        case url
        case price
        case priority
        case status
        case memo
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(item: WishItem, householdID: UUID, userID: UUID) {
        self.id = item.id
        self.householdID = householdID
        self.name = item.name
        self.url = item.url
        self.price = item.price
        self.priority = item.priority.rawValue
        self.status = item.status.rawValue
        self.memo = item.memo
        self.createdBy = userID
        self.createdAt = RemoteDate.format(item.createdAt)
        self.updatedAt = RemoteDate.format(item.updatedAt)
    }
}

enum RemoteDate {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFormatter.date(from: value) ?? fallbackFormatter.date(from: value)
    }

    static func format(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}
