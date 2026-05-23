import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @State private var newItemName = ""
    @State private var newItemStore: StoreType = .any

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [StockTheme.sky.opacity(0.14), StockTheme.softBackground, StockTheme.lemon.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        addPanel

                        SectionHeader(title: "未購入", systemImage: "cart.fill")
                        if activeItems.isEmpty {
                            EmptyStateView(systemImage: "checkmark.circle.fill", title: "買い物リストは空です", message: "必要になったものを追加してください。")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(activeItems) { item in
                                    ShoppingRow(item: item) {
                                        complete(item)
                                    }
                                }
                            }
                        }

                        if !completedItems.isEmpty {
                            SectionHeader(title: "購入済み", systemImage: "checkmark.circle.fill")
                            VStack(spacing: 8) {
                                ForEach(completedItems.prefix(10)) { item in
                                    HStack {
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(item.completedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("買い物")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(StockTheme.mint, in: Circle())
                Text("買うものを追加")
                    .font(.headline.weight(.black))
                Spacer()
            }

            HStack(spacing: 10) {
                TextField("牛乳、洗剤、卵など", text: $newItemName)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)

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
                        .font(.title2)
                }
                .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var activeItems: [ShoppingItem] {
        items.filter { $0.status == .active }
            .sorted { $0.priority.shoppingRank > $1.priority.shoppingRank }
    }

    private var completedItems: [ShoppingItem] {
        items.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func addManualItem() {
        Task {
            do {
                _ = try await appState.inventoryStore.addShoppingItem(
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
    }

    private func complete(_ item: ShoppingItem) {
        Task {
            do {
                try await appState.inventoryStore.completeShoppingItem(id: item.id)
                appState.showToast("購入済みにしました")
            } catch {
                appState.showToast(error.localizedDescription)
            }
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
                    .font(.title2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(StockTheme.mint)

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
        .padding(14)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(item.priority.color.opacity(0.2), lineWidth: 1)
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
