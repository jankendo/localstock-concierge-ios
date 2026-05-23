import Foundation

struct ReceiptParseResult {
    var storeName: String?
    var purchasedAt: Date?
    var totalAmount: Int?
    var items: [ReceiptCandidate]

    var encodedJSON: String? {
        let payload: [String: Any] = [
            "store_name": storeName as Any,
            "purchased_at": purchasedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
            "total_amount": totalAmount as Any,
            "items": items.map { $0.jsonObject }
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct ReceiptCandidate: Identifiable, Hashable {
    let id = UUID()
    var rawName: String
    var normalizedName: String
    var quantity: Double
    var unit: String
    var category: ProductCategory
    var price: Int?
    var confidence: Double
    var isSelected: Bool = true

    var jsonObject: [String: Any] {
        [
            "raw_name": rawName,
            "normalized_name": normalizedName,
            "quantity": quantity,
            "unit": unit,
            "category": category.label,
            "price": price as Any,
            "confidence": confidence
        ]
    }
}

enum ReceiptParser {
    static func parse(rawText: String, llmService: (any LocalLLMService)?) async -> ReceiptParseResult {
        if let llmService,
           let parsed = try? await parseWithLLM(rawText: rawText, service: llmService) {
            return parsed
        }
        return parseHeuristically(rawText: rawText)
    }

    private static func parseWithLLM(rawText: String, service: any LocalLLMService) async throws -> ReceiptParseResult {
        let prompt = """
        \(LLMPrompts.receiptSystemPrompt)

        OCR:
        \(rawText)
        """
        let output = try await service.generate(prompt: prompt, mode: .fastParse)
        guard let json = output.firstJSONObject,
              let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolRouterError.invalidJSON
        }

        let itemsPayload = root["items"] as? [[String: Any]] ?? []
        let items = itemsPayload.compactMap { item -> ReceiptCandidate? in
            guard let rawName = item["raw_name"] as? String ?? item["name"] as? String else { return nil }
            let normalized = item["normalized_name"] as? String ?? rawName
            let quantity = item["quantity"] as? Double ?? Double(item["quantity"] as? Int ?? 1)
            let unit = item["unit"] as? String ?? "個"
            let category = ProductCategory(label: item["category"] as? String) ?? .other
            let price = item["price"] as? Int
            let confidence = item["confidence"] as? Double ?? 0.75
            return ReceiptCandidate(rawName: rawName, normalizedName: normalized, quantity: quantity, unit: unit, category: category, price: price, confidence: confidence)
        }

        return ReceiptParseResult(
            storeName: root["store_name"] as? String,
            purchasedAt: DateParser.parse(root["purchased_at"] as? String),
            totalAmount: root["total_amount"] as? Int,
            items: items
        )
    }

    private static func parseHeuristically(rawText: String) -> ReceiptParseResult {
        let ignoredKeywords = ["合計", "小計", "税", "現計", "お預り", "釣", "ポイント", "値引", "クレジット", "電子マネー", "領収"]
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidates = lines.compactMap { line -> ReceiptCandidate? in
            guard ignoredKeywords.contains(where: { line.contains($0) }) == false else { return nil }
            guard line.count >= 2 else { return nil }

            let price = line.receiptPrice
            let name = line
                .replacingOccurrences(of: #"[\d,]+円?$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { return nil }

            let normalized = normalizeProductName(name)
            return ReceiptCandidate(
                rawName: name,
                normalizedName: normalized,
                quantity: 1,
                unit: defaultUnit(for: normalized),
                category: guessCategory(for: normalized),
                price: price,
                confidence: price == nil ? 0.52 : 0.68
            )
        }

        return ReceiptParseResult(storeName: lines.first, purchasedAt: nil, totalAmount: nil, items: Array(candidates.prefix(20)))
    }

    private static func normalizeProductName(_ name: String) -> String {
        let normalized = name.normalizedForSearch
        let dictionary: [(String, String)] = [
            ("tp", "トイレットペーパー"),
            ("トイペ", "トイレットペーパー"),
            ("ペーパー", "トイレットペーパー"),
            ("ティッシュ", "ティッシュ"),
            ("アタック", "洗濯洗剤"),
            ("洗剤", "洗濯洗剤"),
            ("牛乳", "牛乳"),
            ("卵", "卵"),
            ("たまご", "卵"),
            ("米", "米")
        ]
        return dictionary.first(where: { normalized.contains($0.0.normalizedForSearch) })?.1 ?? name
    }

    private static func defaultUnit(for name: String) -> String {
        if name.contains("牛乳") { return "本" }
        if name.contains("卵") { return "パック" }
        if name.contains("米") { return "袋" }
        if name.contains("ペーパー") { return "パック" }
        if name.contains("洗剤") { return "袋" }
        return "個"
    }

    private static func guessCategory(for name: String) -> ProductCategory {
        if ["牛乳", "卵", "米"].contains(where: { name.contains($0) }) { return .food }
        if name.contains("洗剤") { return .laundry }
        if name.contains("シャンプー") || name.contains("ソープ") { return .bath }
        if name.contains("ラップ") || name.contains("ホイル") { return .kitchen }
        if name.contains("ペーパー") || name.contains("ティッシュ") { return .dailyGoods }
        return .other
    }
}

private enum DateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private extension ProductCategory {
    init?(label: String?) {
        guard let label else { return nil }
        if let category = ProductCategory(rawValue: label) {
            self = category
            return
        }
        if let match = ProductCategory.allCases.first(where: { $0.label == label }) {
            self = match
            return
        }
        return nil
    }
}

private extension String {
    var receiptPrice: Int? {
        let pattern = #"(\d{2,6})\s*円?$"#
        guard let range = range(of: pattern, options: .regularExpression) else { return nil }
        let digits = self[range].filter(\.isNumber)
        return Int(String(digits))
    }

    var firstJSONObject: String? {
        guard let start = firstIndex(of: "{"), let end = lastIndex(of: "}") else { return nil }
        return String(self[start...end])
    }
}
