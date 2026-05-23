import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @Query(sort: \ShoppingItem.createdAt) private var shoppingItems: [ShoppingItem]
    @State private var nfcService = NFCService()
    @State private var nfcMessage = "未実行"
    @State private var email = ""
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Supabase共有") {
                    HStack {
                        Text("状態")
                        Spacer()
                        StatusPill(text: appState.cloudAuth.status.label, color: cloudStatusColor)
                    }

                    if let lastSyncAt = appState.inventoryStore.lastSyncAt {
                        LabeledContent("最終同期", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    Text(appState.inventoryStore.syncMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = appState.inventoryStore.syncError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    switch appState.cloudAuth.status {
                    case .unconfigured:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ビルド設定にSupabase URLとpublishable keyを入れると、同じ世帯の在庫を共同利用できます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("RLSで世帯メンバーだけが読めます", systemImage: "lock.shield")
                        }
                    case .signedOut, .failed(_):
                        TextField("メールアドレス", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            sendMagicLink()
                        } label: {
                            Label("メールリンクでログイン", systemImage: "envelope.badge")
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    case .signingIn:
                        HStack {
                            ProgressView()
                            Text("ログインメールを送信中")
                        }
                    case .signedIn(_, let signedInEmail):
                        if let signedInEmail {
                            LabeledContent("アカウント", value: signedInEmail)
                        }
                        if let householdName = appState.inventoryStore.householdName {
                            LabeledContent("世帯", value: householdName)
                        }
                        if let householdInviteCode = appState.inventoryStore.householdInviteCode {
                            LabeledContent("招待コード", value: householdInviteCode)
                        }

                        HStack {
                            TextField("招待コード", text: $inviteCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            Button {
                                joinHousehold()
                            } label: {
                                Image(systemName: "person.badge.plus")
                            }
                            .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Button {
                            Task { await appState.inventoryStore.syncNow() }
                        } label: {
                            Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(appState.inventoryStore.isSyncing)

                        Button(role: .destructive) {
                            Task { await appState.cloudAuth.signOut() }
                        } label: {
                            Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                Section("Gemma 4") {
                    HStack {
                        Text("モデル")
                        Spacer()
                        StatusPill(text: appState.modelManager.state.label, color: modelStatusColor)
                    }

                    Text(appState.modelManager.localModelURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        appState.modelManager.startInitialDownload()
                    } label: {
                        Label("モデルをダウンロード", systemImage: "arrow.down.circle")
                    }
                    .disabled(appState.modelManager.isModelReady || isDownloading)
                }

                Section("プライバシー") {
                    Label("レシート画像は保存しない", systemImage: "photo.badge.checkmark")
                    Label("OCRとGemma推論は端末内処理", systemImage: "iphone.gen3")
                    Label("在庫共有だけSupabaseへ同期", systemImage: "person.2.badge.gearshape")
                }

                Section("NFC") {
                    Text(nfcMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        startNFC()
                    } label: {
                        Label("NFCタグを読む", systemImage: "wave.3.right.circle")
                    }
                }

                Section("バックアップ") {
                    Button {
                        exportBackup()
                    } label: {
                        Label("JSONバックアップを書き出す", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [StockTheme.softBackground, StockTheme.mint.opacity(0.12), StockTheme.sky.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                nfcService.onURI = handleNFCURL
                nfcService.onMessage = { message in
                    nfcMessage = message
                }
            }
        }
    }

    private var isDownloading: Bool {
        if case .downloading = appState.modelManager.state { return true }
        return false
    }

    private var modelStatusColor: Color {
        switch appState.modelManager.state {
        case .ready:
            return .green
        case .downloading:
            return .blue
        case .failed(_):
            return .red
        case .checking, .missing:
            return .orange
        }
    }

    private func startNFC() {
        nfcService.beginScan()
    }

    private func handleNFCURL(_ url: URL) {
        nfcMessage = url.absoluteString
        guard url.scheme == "stockmate" || url.scheme == "localstock" else { return }
        let components = url.pathComponents.filter { $0 != "/" }

        if components.contains("product"), let slug = components.last {
            let matched = products.first { product in
                product.normalizedName.contains(slug.normalizedForSearch)
                    || product.aliases.map(\.normalizedForSearch).contains(where: { $0.contains(slug.normalizedForSearch) })
            }
            if let matched {
                Task {
                    do {
                        _ = try await appState.inventoryStore.recordOpened(productId: matched.id, quantity: 1, source: .nfc, note: url.absoluteString)
                        appState.showToast("\(matched.name)をNFCから開封記録しました")
                    } catch {
                        appState.showToast(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func exportBackup() {
        let payload: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: .now),
            "products": products.map { product in
                [
                    "id": product.id.uuidString,
                    "name": product.name,
                    "category": product.category.rawValue,
                    "location": product.locationName,
                    "unit": product.unit,
                    "management_type": product.managementType.rawValue,
                    "min_stock": product.minStock,
                    "ideal_stock": product.idealStock,
                    "aliases": product.aliases
                ] as [String: Any]
            },
            "events": events.map { event in
                [
                    "id": event.id.uuidString,
                    "product_id": event.productId.uuidString,
                    "type": event.type.rawValue,
                    "quantity": event.quantity,
                    "source": event.source.rawValue,
                    "note": event.note as Any,
                    "confidence": event.confidence,
                    "created_at": ISO8601DateFormatter().string(from: event.createdAt)
                ] as [String: Any]
            },
            "shopping_items": shoppingItems.map { item in
                [
                    "id": item.id.uuidString,
                    "product_id": item.productId?.uuidString as Any,
                    "name": item.name,
                    "quantity": item.quantity as Any,
                    "unit": item.unit as Any,
                    "store_type": item.storeType.rawValue,
                    "priority": item.priority.rawValue,
                    "reason": item.reason,
                    "status": item.status.rawValue
                ] as [String: Any]
            }
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("localstock-backup-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            appState.showToast("バックアップを書き出しました")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private var cloudStatusColor: Color {
        switch appState.cloudAuth.status {
        case .signedIn:
            return .green
        case .signingIn:
            return .blue
        case .failed:
            return .red
        case .unconfigured, .signedOut:
            return .orange
        }
    }

    private func sendMagicLink() {
        Task {
            do {
                try await appState.cloudAuth.sendMagicLink(email: email)
                appState.showToast("ログインメールを送信しました")
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }

    private func joinHousehold() {
        Task {
            do {
                try await appState.inventoryStore.joinHousehold(inviteCode: inviteCode)
                inviteCode = ""
                appState.showToast("世帯に参加しました")
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }
}
