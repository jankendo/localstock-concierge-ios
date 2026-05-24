import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @Query(sort: \WishItem.createdAt) private var wishItems: [WishItem]
    @State private var addMode: ShoppingAddMode = .shopping
    @State private var newItemName = ""
    @State private var newItemStore: StoreType = .any
    @State private var newWishPriority: Priority = .medium
    @State private var newWishMemo = ""

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

                        SectionHeader(title: "欲しいもの", systemImage: "sparkles")
                        if activeWishItems.isEmpty {
                            EmptyStateView(systemImage: "sparkles", title: "欲しいものは空です", message: "家具、家電、収納用品などを家族メモとして残せます。")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(activeWishItems) { item in
                                    WishRow(item: item) {
                                        markWishPurchased(item)
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
                Image(systemName: addMode.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(addMode.tint, in: Circle())
                Text(addMode.title)
                    .font(.headline.weight(.black))
                Spacer()
            }

            Picker("追加先", selection: $addMode) {
                ForEach(ShoppingAddMode.allCases) { mode in
                    Text(mode.segmentTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                TextField(addMode.placeholder, text: $newItemName)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)

                if addMode == .shopping {
                    Picker("店", selection: $newItemStore) {
                        ForEach(StoreType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        Picker("優先度", selection: $newWishPriority) {
                            ForEach(Priority.allCases) { priority in
                                Text(priority.label).tag(priority)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("メモ/URL 任意", text: $newWishMemo)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    addManualEntry()
                } label: {
                    Label(addMode.buttonTitle, systemImage: "plus.circle.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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

    private var activeWishItems: [WishItem] {
        wishItems.filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.priority.shoppingRank == rhs.priority.shoppingRank {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.priority.shoppingRank > rhs.priority.shoppingRank
            }
    }

    private func addManualEntry() {
        switch addMode {
        case .shopping:
            addManualItem()
        case .wish:
            addWishItem()
        }
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

    private func addWishItem() {
        Task {
            do {
                _ = try await appState.inventoryStore.addWishItem(
                    name: newItemName.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: newWishMemo.urlCandidate,
                    price: nil,
                    priority: newWishPriority,
                    memo: newWishMemo
                )
                newItemName = ""
                newWishMemo = ""
                appState.showToast("欲しいものに追加しました")
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

    private func markWishPurchased(_ item: WishItem) {
        Task {
            do {
                try await appState.inventoryStore.markWishPurchased(id: item.id)
                appState.showToast("欲しいものを購入済みにしました")
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

struct WishRow: View {
    let item: WishItem
    let onPurchased: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onPurchased) {
                Image(systemName: "checkmark.circle")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(StockTheme.coral)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)

                if let memo = item.memo, memo.isEmpty == false {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let url = item.url {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            StatusPill(text: item.priority.label, color: item.priority.color)
        }
        .padding(14)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StockTheme.coral.opacity(0.18), lineWidth: 1)
        }
    }
}

private enum ShoppingAddMode: String, CaseIterable, Identifiable {
    case shopping
    case wish

    var id: String { rawValue }

    var segmentTitle: String {
        switch self {
        case .shopping:
            return "買う"
        case .wish:
            return "ほしい"
        }
    }

    var title: String {
        switch self {
        case .shopping:
            return "買うものを追加"
        case .wish:
            return "欲しいものを追加"
        }
    }

    var buttonTitle: String {
        switch self {
        case .shopping:
            return "買い物に追加"
        case .wish:
            return "欲しいものに追加"
        }
    }

    var placeholder: String {
        switch self {
        case .shopping:
            return "牛乳、洗剤、卵など"
        case .wish:
            return "棚、炊飯器、収納ボックスなど"
        }
    }

    var systemImage: String {
        switch self {
        case .shopping:
            return "cart.badge.plus"
        case .wish:
            return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .shopping:
            return StockTheme.mint
        case .wish:
            return StockTheme.coral
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

private extension String {
    var urlCandidate: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return nil }
        return trimmed
    }
}
