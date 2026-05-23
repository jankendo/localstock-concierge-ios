import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class InventoryStore {
    private var modelContext: ModelContext?
    private var authController: SupabaseAuthController?
    private var cloud: SupabaseInventoryCloud?

    var isSyncing = false
    var lastSyncAt: Date?
    var syncError: String?
    var syncMessage = "端末内キャッシュで動作中"
    var householdName: String?
    var householdInviteCode: String?

    var canUseCloud: Bool {
        authController?.status.isSignedIn == true && cloud != nil
    }

    func configure(modelContext: ModelContext, authController: SupabaseAuthController) {
        self.modelContext = modelContext
        self.authController = authController
        if let client = authController.client {
            cloud = SupabaseInventoryCloud(client: client)
        } else {
            cloud = nil
        }
    }

    func syncNow() async {
        guard canUseCloud, let cloud = cloud, let repository = repository else {
            syncMessage = "Supabase未接続。端末内だけで保存しています。"
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let snapshot = try await cloud.loadSnapshot()
            try await refreshHouseholdInfo()
            if snapshot.products.isEmpty {
                try await pushFullSnapshot()
                syncMessage = "このiPhoneの在庫をSupabaseへ初期同期しました。"
            } else {
                try merge(snapshot)
                syncMessage = "Supabaseから最新の共有在庫を取得しました。"
            }
            lastSyncAt = .now

            if (try? repository.activeProducts().isEmpty) == true {
                SeedData.ensureSeeded(in: try requireContext())
                try await pushFullSnapshot()
            }
        } catch {
            syncError = error.localizedDescription
            syncMessage = "同期に失敗しました。端末内キャッシュは利用できます。"
        }
    }

    func joinHousehold(inviteCode: String) async throws {
        guard canUseCloud, let cloud = cloud else { throw InventoryStoreError.notConfigured }
        try await cloud.joinHousehold(inviteCode: inviteCode)
        try await refreshHouseholdInfo()
        await syncNow()
    }

    @discardableResult
    func createProduct(_ draft: ProductDraft) async throws -> Product {
        let product = try requireRepository().createProduct(draft)
        try await pushProducts([product])
        return product
    }

    @discardableResult
    func recordPurchase(productId: UUID, quantity: Double, unit: String?, source: EventSource, confidence: Double, note: String?) async throws -> InventoryEvent {
        let event = try requireRepository().recordPurchase(productId: productId, quantity: quantity, unit: unit, source: source, confidence: confidence, note: note)
        try await pushFullSnapshot()
        return event
    }

    @discardableResult
    func recordOpened(productId: UUID, quantity: Double, source: EventSource, note: String?) async throws -> InventoryEvent {
        let event = try requireRepository().recordOpened(productId: productId, quantity: quantity, source: source, note: note)
        try await pushFullSnapshot()
        return event
    }

    @discardableResult
    func addShoppingItem(productId: UUID?, name: String, quantity: Double?, unit: String?, storeType: StoreType, priority: Priority, reason: String) async throws -> ShoppingItem {
        let item = try requireRepository().addShoppingItem(productId: productId, name: name, quantity: quantity, unit: unit, storeType: storeType, priority: priority, reason: reason)
        try await pushFullSnapshot()
        return item
    }

    func completeShoppingItem(id: UUID) async throws {
        try requireRepository().completeShoppingItem(id: id)
        if canUseCloud {
            try await cloud?.completeShoppingItem(id: id)
        }
        try await pushShoppingItems()
    }

    @discardableResult
    func saveReceipt(rawText: String, parsedJSON: String?, storeName: String?, purchasedAt: Date?, totalAmount: Int?, imageLocalPath: String?) async throws -> Receipt {
        let receipt = try requireRepository().saveReceipt(
            rawText: rawText,
            parsedJSON: parsedJSON,
            storeName: storeName,
            purchasedAt: purchasedAt,
            totalAmount: totalAmount,
            imageLocalPath: imageLocalPath
        )
        try await pushReceipts([receipt])
        return receipt
    }

    func pushFullSnapshot() async throws {
        guard canUseCloud, let cloud = cloud, let repository = repository else { return }
        try await cloud.upsertProducts(repository.products())
        try await cloud.upsertEvents(repository.allEvents())
        try await cloud.upsertShoppingItems(try localShoppingItems())
        try await cloud.upsertReceipts(try localReceipts())
        lastSyncAt = .now
        syncMessage = "Supabaseへ保存しました。"
    }

    private var repository: SwiftDataInventoryRepository? {
        guard let modelContext else { return nil }
        return SwiftDataInventoryRepository(context: modelContext)
    }

    private func requireRepository() throws -> SwiftDataInventoryRepository {
        guard let repository else { throw InventoryStoreError.notConfigured }
        return repository
    }

    private func requireContext() throws -> ModelContext {
        guard let modelContext else { throw InventoryStoreError.notConfigured }
        return modelContext
    }

    private func pushProducts(_ products: [Product]) async throws {
        guard canUseCloud else { return }
        try await cloud?.upsertProducts(products)
        lastSyncAt = .now
    }

    private func pushShoppingItems() async throws {
        guard canUseCloud else { return }
        try await cloud?.upsertShoppingItems(try localShoppingItems())
        lastSyncAt = .now
    }

    private func pushReceipts(_ receipts: [Receipt]) async throws {
        guard canUseCloud else { return }
        try await cloud?.upsertReceipts(receipts)
        lastSyncAt = .now
    }

    private func refreshHouseholdInfo() async throws {
        guard canUseCloud, let cloud = cloud else { return }
        if let household = try await cloud.currentHousehold() {
            householdName = household.name
            householdInviteCode = household.inviteCode
        }
    }

    private func localShoppingItems() throws -> [ShoppingItem] {
        try requireContext().fetch(FetchDescriptor<ShoppingItem>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func localReceipts() throws -> [Receipt] {
        try requireContext().fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    private func merge(_ snapshot: LocalStockRemoteSnapshot) throws {
        let context = try requireContext()

        let localEvents = try context.fetch(FetchDescriptor<InventoryEvent>())
        let eventProductIDs = Set(localEvents.map(\.productId))
        var localProducts = try context.fetch(FetchDescriptor<Product>())
            .reduce(into: [UUID: Product]()) { $0[$1.id] = $1 }
        var localProductsByName = localProducts.values.reduce(into: [String: Product]()) { partial, product in
            partial[product.normalizedName] = product
        }
        for incoming in snapshot.products {
            if let existing = localProducts[incoming.id] {
                existing.copyValues(from: incoming)
            } else if let sameName = localProductsByName[incoming.normalizedName], eventProductIDs.contains(sameName.id) == false {
                sameName.copyIdentityAndValues(from: incoming)
                localProducts[incoming.id] = sameName
                localProductsByName[incoming.normalizedName] = sameName
            } else {
                context.insert(incoming)
                localProducts[incoming.id] = incoming
                localProductsByName[incoming.normalizedName] = incoming
            }
        }

        let eventIDs = Set(localEvents.map(\.id))
        for incoming in snapshot.events where eventIDs.contains(incoming.id) == false {
            context.insert(incoming)
        }

        var localItems = try context.fetch(FetchDescriptor<ShoppingItem>())
            .reduce(into: [UUID: ShoppingItem]()) { $0[$1.id] = $1 }
        for incoming in snapshot.shoppingItems {
            if let existing = localItems[incoming.id] {
                existing.copyValues(from: incoming)
            } else {
                context.insert(incoming)
                localItems[incoming.id] = incoming
            }
        }

        let receiptIDs = Set(try context.fetch(FetchDescriptor<Receipt>()).map(\.id))
        for incoming in snapshot.receipts where receiptIDs.contains(incoming.id) == false {
            context.insert(incoming)
        }

        try context.save()
    }
}

enum InventoryStoreError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "在庫ストアが初期化されていません。"
        }
    }
}

private extension Product {
    func copyIdentityAndValues(from other: Product) {
        id = other.id
        copyValues(from: other)
    }

    func copyValues(from other: Product) {
        name = other.name
        normalizedName = other.normalizedName
        category = other.category
        locationName = other.locationName
        unit = other.unit
        managementType = other.managementType
        minStock = other.minStock
        idealStock = other.idealStock
        cycleDays = other.cycleDays
        leadDays = other.leadDays
        barcode = other.barcode
        aliases = other.aliases
        isActive = other.isActive
        createdAt = other.createdAt
        updatedAt = other.updatedAt
    }
}

private extension ShoppingItem {
    func copyValues(from other: ShoppingItem) {
        productId = other.productId
        name = other.name
        quantity = other.quantity
        unit = other.unit
        storeType = other.storeType
        priority = other.priority
        reason = other.reason
        status = other.status
        createdAt = other.createdAt
        completedAt = other.completedAt
    }
}
