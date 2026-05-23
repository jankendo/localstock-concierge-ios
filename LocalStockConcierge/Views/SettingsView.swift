import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @Query(sort: \ShoppingItem.createdAt) private var shoppingItems: [ShoppingItem]
    @State private var nfcService = NFCService()
    @State private var nfcMessage = "未実行"

    var body: some View {
        NavigationStack {
            List {
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
                    Label("クラウド同期なし", systemImage: "icloud.slash")
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
            .navigationTitle("設定")
            .onAppear {
                nfcService.onURI = handleNFCURL
                nfcService.onMessage = { message in
                    nfcMessage = message
                }
            }
        }
    }

    private var repository: SwiftDataInventoryRepository {
        SwiftDataInventoryRepository(context: modelContext)
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
        case .failed:
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
                do {
                    _ = try repository.recordOpened(productId: matched.id, quantity: 1, source: .nfc, note: url.absoluteString)
                    appState.showToast("\(matched.name)をNFCから開封記録しました")
                } catch {
                    appState.showToast(error.localizedDescription)
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
}
