import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @Query(sort: \ShoppingItem.createdAt) private var shoppingItems: [ShoppingItem]
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @State private var isAddingProduct = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [StockTheme.softBackground, StockTheme.mint.opacity(0.16), StockTheme.coral.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        if shouldShowSetupChecklist {
                            setupChecklist
                        }
                        quickActions
                        metrics

                        SectionHeader(title: "今日の提案", systemImage: "lightbulb.max.fill")
                        if alerts.isEmpty {
                            EmptyStateView(systemImage: "checkmark.circle.fill", title: "今日は落ち着いています", message: "買い物候補はありません。")
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

                        SectionHeader(title: "買い物リスト", systemImage: "cart.fill")
                        if activeShopping.isEmpty {
                            Text("買い物候補はありません。")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
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
            }
            .navigationTitle("ふたり在庫")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $isAddingProduct) {
                ProductEditorView()
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                StatusPill(text: appState.cloudAuth.status.label, color: appState.cloudAuth.status.isSignedIn ? .green : .orange, systemImage: "person.2.fill")
                Text("今日の在庫")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(StockTheme.ink)
                Text("迷ったら下の大きいボタンから始めます")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image("ConciergeHero")
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 118)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "すぐやる", systemImage: "hand.tap.fill")

            VStack(spacing: 10) {
                NextActionCard(
                    title: "レシートを読む",
                    subtitle: "買ったものを写真から入れる",
                    systemImage: "doc.text.viewfinder",
                    tint: StockTheme.sky
                ) {
                    appState.selectedTab = .receipt
                }

                NextActionCard(
                    title: "買い物を見る",
                    subtitle: "今日買うものだけ確認する",
                    systemImage: "cart.fill",
                    tint: StockTheme.mint
                ) {
                    appState.selectedTab = .shopping
                }

                NextActionCard(
                    title: "ストックを開けた",
                    subtitle: "在庫で「開けた」を押す",
                    systemImage: "shippingbox.and.arrow.backward.fill",
                    tint: StockTheme.coral
                ) {
                    appState.selectedTab = .inventory
                }

                NextActionCard(
                    title: "家族で共有する",
                    subtitle: "Supabaseログインと招待コード",
                    systemImage: "person.2.fill",
                    tint: .orange
                ) {
                    appState.selectedTab = .settings
                }
            }
        }
    }

    private var shouldShowSetupChecklist: Bool {
        appState.modelManager.isModelReady == false
            || products.filter(\.isActive).isEmpty
            || receipts.isEmpty
            || appState.cloudAuth.status.isSignedIn == false
    }

    private var setupChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "はじめてならここから", systemImage: "checklist")

            VStack(spacing: 10) {
                SetupStepCard(
                    title: "AI相談を準備",
                    detail: "初回だけモデルを保存します",
                    isDone: appState.modelManager.isModelReady,
                    systemImage: "sparkles",
                    tint: StockTheme.sky,
                    actionTitle: "準備"
                ) {
                    appState.isModelSetupPresented = true
                }

                SetupStepCard(
                    title: "よく買うものを登録",
                    detail: "トイペ、洗剤、牛乳などから始めます",
                    isDone: products.filter(\.isActive).isEmpty == false,
                    systemImage: "shippingbox.fill",
                    tint: StockTheme.mint,
                    actionTitle: "登録"
                ) {
                    isAddingProduct = true
                }

                SetupStepCard(
                    title: "レシートを1枚読む",
                    detail: "買ったものを候補として取り込みます",
                    isDone: receipts.isEmpty == false,
                    systemImage: "doc.text.viewfinder",
                    tint: StockTheme.lemon,
                    actionTitle: "読む"
                ) {
                    appState.selectedTab = .receipt
                }

                SetupStepCard(
                    title: "家族で共有",
                    detail: "Supabaseに接続して招待コードを使います",
                    isDone: appState.cloudAuth.status.isSignedIn,
                    systemImage: "person.2.fill",
                    tint: .orange,
                    actionTitle: "共有"
                ) {
                    appState.selectedTab = .settings
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricTile(title: "今買う", value: "\(alerts.filter { $0.state.status == .buyNow }.count)", systemImage: "exclamationmark.triangle.fill", tint: StockTheme.coral)
            MetricTile(title: "そろそろ", value: "\(alerts.filter { $0.state.status == .buySoon }.count)", systemImage: "clock.fill", tint: StockTheme.lemon)
            MetricTile(title: "買い物", value: "\(activeShopping.count)", systemImage: "cart.fill", tint: StockTheme.sky)
        }
    }

    private var alerts: [InventoryAlert] {
        InventoryCalculator.alerts(products: products.filter(\.isActive), events: events)
    }

    private var activeShopping: [ShoppingItem] {
        shoppingItems.filter { $0.status == .active }
    }

    private func recordOpened(_ product: Product) {
        Task {
            do {
                _ = try await appState.inventoryStore.recordOpened(productId: product.id, quantity: 1, source: .manual, note: "ホームから開封")
                appState.showToast("\(product.name)を開封として記録しました")
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }

    private func addShopping(_ alert: InventoryAlert) {
        Task {
            do {
                _ = try await appState.inventoryStore.addShoppingItem(
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
    }

    private func completeShopping(_ item: ShoppingItem) {
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text(alert.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer()
                StatusPill(text: alert.state.status.label, color: alert.state.status.tint)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    openedButton
                    shoppingButton
                }

                VStack(spacing: 8) {
                    openedButton.frame(maxWidth: .infinity)
                    shoppingButton.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(alert.state.status.tint.opacity(0.24), lineWidth: 1)
        }
    }

    private var openedButton: some View {
        Button(action: onOpened) {
            Label("開けた", systemImage: "shippingbox.and.arrow.backward.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(alert.product.name)を開けたと記録")
    }

    private var shoppingButton: some View {
        Button(action: onAddShopping) {
            Label("買い物へ", systemImage: "cart.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("\(alert.product.name)を買い物リストへ追加")
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
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Button(action: onComplete) {
                Label("買った", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(item.name)を購入済みにする")
        }
        .padding(12)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
