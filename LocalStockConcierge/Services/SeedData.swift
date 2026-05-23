import Foundation
import SwiftData

enum SeedData {
    private static let seededKey = "seeded.default.products.v1"

    @MainActor
    static func ensureSeeded(in context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: seededKey) == false else { return }

        let existingCount = (try? context.fetchCount(FetchDescriptor<Product>())) ?? 0
        guard existingCount == 0 else {
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        for product in defaultProducts {
            context.insert(product)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: seededKey)
        } catch {
            assertionFailure("Seed failed: \(error)")
        }
    }

    static let defaultProducts: [Product] = [
        Product(name: "トイレットペーパー", category: .dailyGoods, locationName: "トイレ収納", unit: "パック", managementType: .unopenedPackage, minStock: 1, idealStock: 2, aliases: ["TP", "トイペ", "トイレット", "ペーパー"]),
        Product(name: "ティッシュ", category: .dailyGoods, locationName: "リビング収納", unit: "箱", managementType: .unopenedPackage, minStock: 2, idealStock: 5, aliases: ["ティッシュペーパー"]),
        Product(name: "洗濯洗剤", category: .laundry, locationName: "洗面所", unit: "袋", managementType: .unopenedPackage, minStock: 1, idealStock: 2, aliases: ["アタック", "洗剤"]),
        Product(name: "柔軟剤", category: .laundry, locationName: "洗面所", unit: "袋", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "食器用洗剤", category: .kitchen, locationName: "キッチン", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "シャンプー", category: .bath, locationName: "浴室収納", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "トリートメント", category: .bath, locationName: "浴室収納", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "ボディソープ", category: .bath, locationName: "浴室収納", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "歯磨き粉", category: .dailyGoods, locationName: "洗面所", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "ハンドソープ", category: .dailyGoods, locationName: "洗面所", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "ゴミ袋", category: .kitchen, locationName: "キッチン", unit: "袋", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "ラップ", category: .kitchen, locationName: "キッチン", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "アルミホイル", category: .kitchen, locationName: "キッチン", unit: "本", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "キッチンペーパー", category: .kitchen, locationName: "キッチン", unit: "ロール", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "排水口ネット", category: .kitchen, locationName: "キッチン", unit: "袋", managementType: .unopenedPackage, minStock: 1, idealStock: 2),
        Product(name: "米", category: .food, locationName: "キッチン", unit: "袋", managementType: .cyclePrediction, minStock: 1, idealStock: 1, cycleDays: 28, aliases: ["お米", "米5kg"]),
        Product(name: "卵", category: .food, locationName: "冷蔵庫", unit: "パック", managementType: .cyclePrediction, minStock: 1, idealStock: 1, cycleDays: 7),
        Product(name: "牛乳", category: .food, locationName: "冷蔵庫", unit: "本", managementType: .cyclePrediction, minStock: 1, idealStock: 2, cycleDays: 4)
    ]
}
