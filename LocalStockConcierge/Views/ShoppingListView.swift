import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @State private var newItemName = ""
    @State private var newItemStore: StoreType = .any

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("買うもの", text: $newItemName)
                            .textInputAutocapitalization(.never)
                        Picker("店", selection: $newItemStore) {
                            ForEach(StoreType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        Button {
                            addManualItem()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("未購入") {
                    ForEach(activeItems) { item in
                        ShoppingRow(item: item) {
                            complete(item)
                        }
                    }
                }

                if !completedItems.isEmpty {
                    Section("購入済み") {
                        ForEach(completedItems.prefix(10)) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.completedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("買い物")
        }
    }

    private var activeItems: [ShoppingItem] {
        items.filter { $0.status == .active }
            .sorted { $0.priority.shoppingRank > $1.priority.shoppingRank }
    }

    private var completedItems: [ShoppingItem] {
        items.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var repository: SwiftDataInventoryRepository {
        SwiftDataInventoryRepository(context: modelContext)
    }

    private func addManualItem() {
        do {
            _ = try repository.addShoppingItem(
                productId: nil,
                name: newItemName.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: 1,
                unit: nil,
                storeType: newItemStore,
                priority: .medium,
                reason: "手動追加"
            )
            newItemName = ""
            appState.showToast("買い物リストに追加しました")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func complete(_ item: ShoppingItem) {
        do {
            try repository.completeShoppingItem(id: item.id)
            appState.showToast("購入済みにしました")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct ShoppingRow: View {
    let item: ShoppingItem
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                    if let quantity = item.quantity {
                        Text("\(quantity.formattedStock)\(item.unit ?? "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: item.priority.label, color: item.priority.color)
                Text(item.storeType.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Priority {
    var shoppingRank: Int {
        switch self {
        case .urgent:
            return 3
        case .high:
            return 2
        case .medium:
            return 1
        case .low:
            return 0
        }
    }

    var color: Color {
        switch self {
        case .urgent:
            return .red
        case .high:
            return .orange
        case .medium:
            return .blue
        case .low:
            return .secondary
        }
    }
}
