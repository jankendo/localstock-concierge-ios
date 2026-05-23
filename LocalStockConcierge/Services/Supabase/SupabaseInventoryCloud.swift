import Foundation
import Supabase

@MainActor
final class SupabaseInventoryCloud {
    private let client: SupabaseClient
    private var cachedHouseholdID: UUID?

    init(client: SupabaseClient) {
        self.client = client
    }

    func ensureHousehold(named name: String = "ふたりの在庫") async throws -> UUID {
        if let cachedHouseholdID {
            return cachedHouseholdID
        }

        let userID = try await currentUserID()
        let memberships: [RemoteHouseholdMembership] = try await client
            .from("localstock_household_members")
            .select("household_id, role")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        if let first = memberships.first {
            cachedHouseholdID = first.householdID
            return first.householdID
        }

        let householdID = UUID()
        try await client
            .from("localstock_households")
            .insert(RemoteHouseholdInsert(id: householdID, name: name, createdBy: userID))
            .execute()

        try await client
            .from("localstock_household_members")
            .insert(RemoteHouseholdMemberInsert(householdID: householdID, userID: userID, role: "owner"))
            .execute()

        cachedHouseholdID = householdID
        return householdID
    }

    func currentUserID() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }

    func loadSnapshot() async throws -> LocalStockRemoteSnapshot {
        let householdID = try await ensureHousehold()

        let productRecords: [RemoteProductRecord] = try await client
            .from("localstock_products")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .execute()
            .value

        let eventRecords: [RemoteInventoryEventRecord] = try await client
            .from("localstock_inventory_events")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        let shoppingRecords: [RemoteShoppingItemRecord] = try await client
            .from("localstock_shopping_items")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        let receiptRecords: [RemoteReceiptRecord] = try await client
            .from("localstock_receipts")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .value

        return LocalStockRemoteSnapshot(
            products: productRecords.map { $0.domainProduct() },
            events: eventRecords.map { $0.domainEvent() },
            shoppingItems: shoppingRecords.map { $0.domainItem() },
            receipts: receiptRecords.map { $0.domainReceipt() }
        )
    }

    func currentHousehold() async throws -> RemoteHouseholdRecord? {
        let householdID = try await ensureHousehold()
        let records: [RemoteHouseholdRecord] = try await client
            .from("localstock_households")
            .select("id, name, invite_code")
            .eq("id", value: householdID.uuidString)
            .execute()
            .value
        return records.first
    }

    func joinHousehold(inviteCode: String) async throws {
        let joinedID: UUID = try await client
            .rpc(
                "localstock_join_household",
                params: RemoteJoinHouseholdParams(inviteCodeInput: inviteCode)
            )
            .execute()
            .value
        cachedHouseholdID = joinedID
    }

    func upsertProducts(_ products: [Product]) async throws {
        guard !products.isEmpty else { return }
        let householdID = try await ensureHousehold()
        let payload = products.map { RemoteProductPayload(product: $0, householdID: householdID) }
        try await client
            .from("localstock_products")
            .upsert(payload)
            .execute()
    }

    func upsertEvents(_ events: [InventoryEvent]) async throws {
        guard !events.isEmpty else { return }
        let householdID = try await ensureHousehold()
        let userID = try await currentUserID()
        let payload = events.map { RemoteInventoryEventPayload(event: $0, householdID: householdID, userID: userID) }
        try await client
            .from("localstock_inventory_events")
            .upsert(payload)
            .execute()
    }

    func upsertShoppingItems(_ items: [ShoppingItem]) async throws {
        guard !items.isEmpty else { return }
        let householdID = try await ensureHousehold()
        let userID = try await currentUserID()
        let payload = items.map { RemoteShoppingItemPayload(item: $0, householdID: householdID, userID: userID) }
        try await client
            .from("localstock_shopping_items")
            .upsert(payload)
            .execute()
    }

    func upsertReceipts(_ receipts: [Receipt]) async throws {
        guard !receipts.isEmpty else { return }
        let householdID = try await ensureHousehold()
        let userID = try await currentUserID()
        let payload = receipts.map { RemoteReceiptPayload(receipt: $0, householdID: householdID, userID: userID) }
        try await client
            .from("localstock_receipts")
            .upsert(payload)
            .execute()
    }

    func completeShoppingItem(id: UUID) async throws {
        let householdID = try await ensureHousehold()
        try await client
            .from("localstock_shopping_items")
            .update(RemoteShoppingUpdate(status: ShoppingStatus.completed.rawValue, completedAt: RemoteDate.format(.now)))
            .eq("household_id", value: householdID.uuidString)
            .eq("id", value: id.uuidString)
            .execute()
    }
}
