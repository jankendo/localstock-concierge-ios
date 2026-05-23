import SwiftData
import SwiftUI

@main
struct LocalStockConciergeApp: App {
    @State private var appState = AppState()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Product.self,
            InventoryEvent.self,
            InventoryState.self,
            ShoppingItem.self,
            WishItem.self,
            Receipt.self,
            AppPreference.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
        }
        .modelContainer(modelContainer)
    }
}
