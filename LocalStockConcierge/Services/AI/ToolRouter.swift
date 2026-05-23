import Foundation

struct ToolExecutionResult: Identifiable {
    let id = UUID()
    let name: String
    let message: String
    let requiresConfirmation: Bool
}

struct ParsedToolCall {
    let name: String
    let arguments: [String: Any]
    let confirmRequired: Bool
}

@MainActor
final class ToolRouter {
    private let repository: any InventoryRepository

    init(repository: any InventoryRepository) {
        self.repository = repository
    }

    func executeModelOutput(_ rawOutput: String) async throws -> [ToolExecutionResult] {
        let calls = try ToolCallParser.parse(rawOutput)
        var results: [ToolExecutionResult] = []

        for call in calls {
            if call.confirmRequired || requiresConfirmation(call) {
                results.append(ToolExecutionResult(name: call.name, message: "確認が必要です: \(call.name)", requiresConfirmation: true))
                continue
            }
            results.append(try execute(call))
        }

        return results
    }

    func execute(_ call: ParsedToolCall) throws -> ToolExecutionResult {
        switch call.name {
        case "search_products":
            let query = try call.string("query")
            let products = try repository.searchProducts(query: query)
            return ToolExecutionResult(name: call.name, message: "\(products.count)件見つかりました。", requiresConfirmation: false)

        case "record_purchase":
            let product = try resolveProduct(call)
            let quantity = try call.double("quantity", defaultValue: 1)
            let unit = call.optionalString("unit")
            let confidence = try call.double("confidence", defaultValue: 0.8)
            _ = try repository.recordPurchase(productId: product.id, quantity: quantity, unit: unit, source: .llmToolCall, confidence: confidence, note: "AI tool call")
            return ToolExecutionResult(name: call.name, message: "\(product.name)を購入として記録しました。", requiresConfirmation: false)

        case "record_opened":
            let product = try resolveProduct(call)
            let quantity = try call.double("quantity", defaultValue: 1)
            _ = try repository.recordOpened(productId: product.id, quantity: quantity, source: .llmToolCall, note: "AI tool call")
            return ToolExecutionResult(name: call.name, message: "\(product.name)を開封として記録しました。", requiresConfirmation: false)

        case "correct_inventory":
            let product = try resolveProduct(call)
            let stock = try call.double("estimated_stock")
            let reason = call.optionalString("reason") ?? "AI補正"
            _ = try repository.correctInventory(productId: product.id, estimatedStock: stock, reason: reason)
            return ToolExecutionResult(name: call.name, message: "\(product.name)の在庫を補正しました。", requiresConfirmation: false)

        case "add_shopping_item":
            let product = try? resolveProduct(call)
            let name = call.optionalString("name") ?? product?.name ?? call.optionalString("product_name")
            guard let name else {
                throw ToolRouterError.invalidArguments("name")
            }
            let item = try repository.addShoppingItem(
                productId: product?.id,
                name: name,
                quantity: try call.double("quantity", defaultValue: 1),
                unit: call.optionalString("unit") ?? product?.unit,
                storeType: StoreType(rawValue: call.optionalString("store_type") ?? "") ?? product?.category.defaultStoreType ?? .any,
                priority: Priority(rawValue: call.optionalString("priority") ?? "") ?? .medium,
                reason: call.optionalString("reason") ?? "AI提案"
            )
            return ToolExecutionResult(name: call.name, message: "\(item.name)を買い物リストに追加しました。", requiresConfirmation: false)

        case "complete_shopping_item":
            let id = try UUID(uuidString: call.string("shopping_item_id")).orThrow(ToolRouterError.invalidArguments("shopping_item_id"))
            try repository.completeShoppingItem(id: id)
            return ToolExecutionResult(name: call.name, message: "買い物リストを購入済みにしました。", requiresConfirmation: false)

        case "suggest_restock":
            let products = try repository.activeProducts()
            let alerts = try InventoryCalculator.alerts(products: products, events: repository.allEvents())
            let message = alerts.prefix(5).map { "\($0.product.name): \($0.reason)" }.joined(separator: "\n")
            return ToolExecutionResult(name: call.name, message: message.isEmpty ? "今すぐ買う候補はありません。" : message, requiresConfirmation: false)

        default:
            throw ToolRouterError.unknownTool(call.name)
        }
    }

    private func resolveProduct(_ call: ParsedToolCall) throws -> Product {
        if let idString = call.optionalString("product_id"), let id = UUID(uuidString: idString), let product = try repository.product(id: id) {
            return product
        }

        let query = call.optionalString("product_name") ?? call.optionalString("name") ?? call.optionalString("query")
        guard let query else {
            throw ToolRouterError.invalidArguments("product_id or product_name")
        }

        let matches = try repository.searchProducts(query: query)
        guard let product = matches.first else {
            throw ToolRouterError.productNeedsConfirmation(query)
        }
        guard matches.count == 1 else {
            throw ToolRouterError.productNeedsConfirmation(query)
        }
        return product
    }

    private func requiresConfirmation(_ call: ParsedToolCall) -> Bool {
        if call.name == "create_product" { return true }
        if call.name == "delete_product" { return true }
        if call.name == "correct_inventory" { return true }
        if (try? call.double("confidence")) ?? 1 < 0.7 { return true }
        return false
    }
}

enum ToolCallParser {
    static func parse(_ rawOutput: String) throws -> [ParsedToolCall] {
        guard let json = rawOutput.firstJSONObject else {
            throw ToolRouterError.invalidJSON
        }
        let data = Data(json.utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolRouterError.invalidJSON
        }

        let callsPayload: [[String: Any]]
        if let calls = root["calls"] as? [[String: Any]] {
            callsPayload = calls
        } else if let calls = root["tool_calls"] as? [[String: Any]] {
            callsPayload = calls
        } else if let name = root["name"] as? String {
            callsPayload = [["name": name, "arguments": root["arguments"] ?? [:], "confirm_required": root["confirm_required"] ?? false]]
        } else {
            return []
        }

        return callsPayload.compactMap { payload in
            let name: String?
            let arguments: [String: Any]

            if let function = payload["function"] as? [String: Any] {
                name = function["name"] as? String
                arguments = function["arguments"] as? [String: Any] ?? [:]
            } else {
                name = payload["name"] as? String
                arguments = payload["arguments"] as? [String: Any] ?? [:]
            }

            guard let name else { return nil }
            return ParsedToolCall(
                name: name,
                arguments: arguments,
                confirmRequired: payload["confirm_required"] as? Bool ?? false
            )
        }
    }
}

enum ToolRouterError: LocalizedError {
    case invalidJSON
    case unknownTool(String)
    case invalidArguments(String)
    case productNeedsConfirmation(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "AI応答のJSONを読み取れませんでした。"
        case .unknownTool(let name):
            return "未対応のツールです: \(name)"
        case .invalidArguments(let key):
            return "引数が不正です: \(key)"
        case .productNeedsConfirmation(let query):
            return "商品を確定できません: \(query)"
        }
    }
}

private extension ParsedToolCall {
    func string(_ key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw ToolRouterError.invalidArguments(key)
        }
        return value
    }

    func optionalString(_ key: String) -> String? {
        arguments[key] as? String
    }

    func double(_ key: String, defaultValue: Double? = nil) throws -> Double {
        if let value = arguments[key] as? Double { return value }
        if let value = arguments[key] as? Int { return Double(value) }
        if let value = arguments[key] as? String, let double = Double(value) { return double }
        if let defaultValue { return defaultValue }
        throw ToolRouterError.invalidArguments(key)
    }
}

private extension Optional {
    func orThrow(_ error: Error) throws -> Wrapped {
        guard let wrapped = self else { throw error }
        return wrapped
    }
}

private extension String {
    var firstJSONObject: String? {
        guard let start = firstIndex(of: "{"), let end = lastIndex(of: "}") else { return nil }
        return String(self[start...end])
    }
}
