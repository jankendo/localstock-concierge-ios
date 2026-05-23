import SwiftData
import SwiftUI

struct ConciergeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @Query(sort: \ShoppingItem.createdAt) private var shoppingItems: [ShoppingItem]
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "今日買うもの、開封記録、レシートの確認を相談できます。")
    ]
    @State private var input = ""
    @State private var isResponding = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [StockTheme.coral.opacity(0.12), StockTheme.softBackground, StockTheme.mint.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image("ConciergeHero")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 84, height: 84)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("在庫コンシェルジュ")
                                            .font(.title3.weight(.black))
                                        Text("今日買うものを短く答えます")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                ForEach(messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                                if isResponding {
                                    ProgressView()
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("今日スーパーで買うものある？", text: $input, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        Button {
                            send()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("コンシェルジュ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("今買うもの") { quickAsk("今日買うものある？") }
                        Button("ドラッグストア") { quickAsk("ドラッグストアで買うものある？") }
                        Button("開封を記録") { quickAsk("トイレットペーパーを開けた") }
                    } label: {
                        Image(systemName: "text.badge.plus")
                    }
                }
            }
        }
    }

    private var repository: SwiftDataInventoryRepository {
        SwiftDataInventoryRepository(context: modelContext)
    }

    private func quickAsk(_ text: String) {
        input = text
        send()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: text))
        isResponding = true

        Task {
            let reply = await makeReply(for: text)
            await MainActor.run {
                messages.append(ChatMessage(role: .assistant, text: reply))
                isResponding = false
            }
        }
    }

    @MainActor
    private func makeReply(for text: String) async -> String {
        let prompt = buildPrompt(userText: text)

        if let service = appState.modelManager.makeLLMService() {
            do {
                let queue = LLMInferenceQueue(service: service)
                let output = try await queue.enqueue(prompt: prompt, mode: .chat)
                if let calls = try? ToolCallParser.parse(output), !calls.isEmpty {
                    let router = ToolRouter(repository: repository, inventoryStore: appState.inventoryStore)
                    let results = try await router.executeModelOutput(output)
                    return results.map(\.message).joined(separator: "\n")
                }
                return output
            } catch {
                return "Gemmaの応答に失敗しました。ローカルDBから見ると、\(deterministicRestockAnswer())\n\n詳細: \(error.localizedDescription)"
            }
        }

        return deterministicRestockAnswer()
    }

    private func deterministicRestockAnswer() -> String {
        let alerts = InventoryCalculator.alerts(products: products.filter(\.isActive), events: events)
        let shopping = shoppingItems.filter { $0.status == .active }

        if alerts.isEmpty && shopping.isEmpty {
            return "今すぐ買う候補はありません。レシート登録や開封記録を続けると、提案の精度が上がります。"
        }

        var lines: [String] = []
        if !alerts.isEmpty {
            lines.append("在庫から見る候補:")
            lines.append(contentsOf: alerts.prefix(6).map { "・\($0.product.name): \($0.reason)" })
        }
        if !shopping.isEmpty {
            lines.append("買い物リスト:")
            lines.append(contentsOf: shopping.prefix(6).map { "・\($0.name): \($0.reason)" })
        }
        return lines.joined(separator: "\n")
    }

    private func buildPrompt(userText: String) -> String {
        let alerts = InventoryCalculator.alerts(products: products.filter(\.isActive), events: events)
        let shopping = shoppingItems.filter { $0.status == .active }
        let recent = events.prefix(12).map { event -> [String: String] in
            let productName = products.first(where: { $0.id == event.productId })?.name ?? "不明"
            return [
                "product": productName,
                "event": event.type.rawValue,
                "date": event.createdAt.formatted(date: .numeric, time: .omitted)
            ]
        }

        let context: [String: Any] = [
            "shopping_items": shopping.map { ["id": $0.id.uuidString, "name": $0.name, "priority": $0.priority.rawValue, "reason": $0.reason] },
            "inventory_alerts": alerts.map { ["product_id": $0.product.id.uuidString, "name": $0.product.name, "status": $0.state.status.rawValue, "reason": $0.reason] },
            "recent_events": recent,
            "available_tools": ToolSchemaProvider.schemas
        ]
        let data = try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        \(LLMPrompts.conciergeSystemPrompt)

        ローカルDBコンテキスト:
        \(json)

        ユーザー:
        \(userText)
        """
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    var role: Role
    var text: String
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 32) }
            Text(message.text)
                .font(.body)
                .padding(12)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(message.role == .user ? StockTheme.sky : Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }
}

enum ToolSchemaProvider {
    static let schemas: [[String: Any]] = [
        [
            "name": "search_products",
            "description": "商品名や別名からローカル商品マスターを検索する",
            "parameters": ["query": "string"]
        ],
        [
            "name": "record_purchase",
            "description": "購入イベントを記録する",
            "parameters": ["product_id": "string", "quantity": "number", "unit": "string", "confidence": "number"]
        ],
        [
            "name": "record_opened",
            "description": "未開封ストックを開封したイベントを記録する",
            "parameters": ["product_id": "string", "quantity": "number"]
        ],
        [
            "name": "add_shopping_item",
            "description": "買い物リストに商品を追加する",
            "parameters": ["product_id": "string", "name": "string", "quantity": "number", "store_type": "string", "priority": "string", "reason": "string"]
        ],
        [
            "name": "suggest_restock",
            "description": "在庫状態と消費周期から買うべきものを提案する",
            "parameters": ["days_ahead": "integer"]
        ]
    ]
}
