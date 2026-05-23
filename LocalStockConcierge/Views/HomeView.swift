import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @Query(sort: \ShoppingItem.createdAt) private var shoppingItems: [ShoppingItem]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metrics

                    SectionHeader(title: "今日の提案", systemImage: "lightbulb.max")
                    if alerts.isEmpty {
                        EmptyStateView(systemImage: "checkmark.circle", title: "今すぐ対応する在庫はありません", message: "レシート読み取りや開封記録を続けると提案精度が上がります。")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(alerts) { alert in
                                AlertRow(alert: alert) {
                                    addShopping(alert)
                                } onOpened: {
                                    recordOpened(alert.product)
                                }
                            }
                        }
                    }

                    SectionHeader(title: "買い物リスト", systemImage: "cart")
                    if activeShopping.isEmpty {
                        Text("買い物候補はありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(activeShopping.prefix(5)) { item in
                                ShoppingCompactRow(item: item) {
                                    completeShopping(item)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("ふたり在庫")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.selectedTab = .concierge
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("コンシェルジュ")
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricTile(title: "今買う", value: "\(alerts.filter { $0.state.status == .buyNow }.count)", systemImage: "exclamationmark.triangle", tint: .red)
            MetricTile(title: "そろそろ", value: "\(alerts.filter { $0.state.status == .buySoon }.count)", systemImage: "clock", tint: .orange)
            MetricTile(title: "買い物", value: "\(activeShopping.count)", systemImage: "cart.fill", tint: .blue)
        }
    }

    private var alerts: [InventoryAlert] {
        InventoryCalculator.alerts(products: products.filter(\.isActive), events: events)
    }

    private var activeShopping: [ShoppingItem] {
        shoppingItems.filter { $0.status == .active }
    }

    private var repository: SwiftDataInventoryRepository {
        SwiftDataInventoryRepository(context: modelContext)
    }

    private func recordOpened(_ product: Product) {
        do {
            _ = try repository.recordOpened(productId: product.id, quantity: 1, source: .manual, note: "ホームから開封")
            appState.showToast("\(product.name)を開封として記録しました")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func addShopping(_ alert: InventoryAlert) {
        do {
            _ = try repository.addShoppingItem(
                productId: alert.product.id,
                name: alert.product.name,
                quantity: max(alert.product.idealStock - alert.state.estimatedStock, 1),
                unit: alert.product.unit,
                storeType: alert.product.category.defaultStoreType,
                priority: alert.state.status == .buyNow ? .urgent : .high,
                reason: alert.reason
            )
            appState.showToast("買い物リストに追加しました")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func completeShopping(_ item: ShoppingItem) {
        do {
            try repository.completeShoppingItem(id: item.id)
            appState.showToast("購入済みにしました")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

struct AlertRow: View {
    let alert: InventoryAlert
    let onAddShopping: () -> Void
    let onOpened: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.product.name)
                        .font(.headline)
                    Text(alert.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: alert.state.status.label, color: alert.state.status.tint)
            }

            HStack {
                Button("開封記録", action: onOpened)
                    .buttonStyle(.bordered)
                Button("買い物へ", action: onAddShopping)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary)
        }
    }
}

struct ShoppingCompactRow: View {
    let item: ShoppingItem
    let onComplete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onComplete) {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
