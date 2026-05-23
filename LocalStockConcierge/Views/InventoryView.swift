import SwiftData
import SwiftUI

struct InventoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @State private var searchText = ""
    @State private var isAddingProduct = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [StockTheme.mint.opacity(0.16), StockTheme.softBackground, StockTheme.coral.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredProducts) { product in
                            ProductInventoryRow(product: product, state: state(for: product)) {
                                recordPurchase(product)
                            } onOpened: {
                                recordOpened(product)
                            }
                        }
                    }
                    .padding()
                }
            }
            .searchable(text: $searchText, prompt: "商品・別名で検索")
            .navigationTitle("在庫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingProduct = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingProduct) {
                ProductEditorView()
            }
        }
    }

    private var filteredProducts: [Product] {
        let active = products.filter(\.isActive)
        guard !searchText.isEmpty else { return active }
        let query = searchText.normalizedForSearch
        return active.filter {
            $0.normalizedName.contains(query) || $0.aliases.map(\.normalizedForSearch).contains(where: { $0.contains(query) })
        }
    }

    private func state(for product: Product) -> InventoryStateSnapshot {
        InventoryCalculator.state(for: product, events: events.filter { $0.productId == product.id })
    }

    private func recordPurchase(_ product: Product) {
        Task {
            do {
                _ = try await appState.inventoryStore.recordPurchase(productId: product.id, quantity: 1, unit: product.unit, source: .manual, confidence: 1, note: "在庫画面から購入")
                appState.showToast("\(product.name)を購入として記録しました")
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }

    private func recordOpened(_ product: Product) {
        Task {
            do {
                _ = try await appState.inventoryStore.recordOpened(productId: product.id, quantity: 1, source: .manual, note: "在庫画面から開封")
                appState.showToast("\(product.name)を開封として記録しました")
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }
}

struct ProductInventoryRow: View {
    let product: Product
    let state: InventoryStateSnapshot
    let onPurchase: () -> Void
    let onOpened: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryBadge(category: product.category)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.headline)
                    Text("\(product.locationName) / \(product.managementType.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: state.status.label, color: state.status.tint)
            }

            HStack(spacing: 14) {
                Label("\(state.estimatedStock.formattedStock)\(product.unit)", systemImage: "shippingbox")
                Label("最低 \(product.minStock.formattedStock)", systemImage: "line.3.horizontal.decrease")
                if let date = state.lastOpenedAt {
                    Label(date.formatted(date: .numeric, time: .omitted), systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button(action: onPurchase) {
                    Label("購入 +1", systemImage: "bag.fill")
                }
                    .buttonStyle(.bordered)
                Button(action: onOpened) {
                    Label("開封 +1", systemImage: "shippingbox.and.arrow.backward.fill")
                }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(state.status.tint.opacity(0.24), lineWidth: 1)
        }
    }
}

struct CategoryBadge: View {
    let category: ProductCategory

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(category.tint, in: Circle())
    }
}

struct ProductEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var name = ""
    @State private var category: ProductCategory = .dailyGoods
    @State private var locationName = ""
    @State private var unit = "個"
    @State private var managementType: ManagementType = .unopenedPackage
    @State private var minStock = 1.0
    @State private var idealStock = 2.0

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("商品名", text: $name)
                    Picker("カテゴリ", selection: $category) {
                        ForEach(ProductCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    TextField("場所", text: $locationName)
                    TextField("単位", text: $unit)
                }

                Section("管理") {
                    Picker("管理方式", selection: $managementType) {
                        ForEach(ManagementType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    Stepper("最低 \(minStock.formattedStock)", value: $minStock, in: 0...99, step: 1)
                    Stepper("理想 \(idealStock.formattedStock)", value: $idealStock, in: 0...99, step: 1)
                }
            }
            .navigationTitle("商品追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                _ = try await appState.inventoryStore.createProduct(ProductDraft(
                    name: name,
                    category: category,
                    locationName: locationName.isEmpty ? "未設定" : locationName,
                    unit: unit.isEmpty ? "個" : unit,
                    managementType: managementType,
                    minStock: minStock,
                    idealStock: idealStock,
                    cycleDays: nil,
                    aliases: []
                ))
                appState.showToast("商品を追加しました")
                dismiss()
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }
}
