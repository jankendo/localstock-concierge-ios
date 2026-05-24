import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    var activeRoute: AppRoute?
    var isModelSetupPresented = false
    var latestToast: String?

    let modelManager = GemmaModelManager()
    let notificationService = NotificationService()
    let cloudAuth = SupabaseAuthController()
    let inventoryStore = InventoryStore()

    private var hasBootstrapped = false

    func bootstrapIfNeeded(modelContext: ModelContext) {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        inventoryStore.configure(modelContext: modelContext, authController: cloudAuth)
        SeedData.ensureSeeded(in: modelContext)
        modelManager.refreshState()
        isModelSetupPresented = !modelManager.isModelReady
        notificationService.requestAuthorizationIfNeeded()

        Task {
            await cloudAuth.refreshSession()
            inventoryStore.configure(modelContext: modelContext, authController: cloudAuth)
            await inventoryStore.syncNow()
        }
    }

    func showToast(_ message: String) {
        latestToast = message
    }

    func handleAuthCallback(_ url: URL, modelContext: ModelContext) {
        Task {
            do {
                try await cloudAuth.handleOpenURL(url)
                inventoryStore.configure(modelContext: modelContext, authController: cloudAuth)
                await inventoryStore.syncNow()
                showToast("Supabase同期を開始しました")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    func saveSupabaseConfiguration(urlString: String, publishableKey: String, modelContext: ModelContext) throws {
        try cloudAuth.saveConfiguration(urlString: urlString, publishableKey: publishableKey)
        inventoryStore.configure(modelContext: modelContext, authController: cloudAuth)
    }

    func clearStoredSupabaseConfiguration(modelContext: ModelContext) {
        cloudAuth.clearStoredConfiguration()
        inventoryStore.configure(modelContext: modelContext, authController: cloudAuth)
    }
}

enum AppRoute: Hashable, Identifiable {
    case product(UUID)
    case shoppingItem(UUID)
    case receipt(UUID)

    var id: String {
        switch self {
        case .product(let id):
            return "product-\(id.uuidString)"
        case .shoppingItem(let id):
            return "shopping-\(id.uuidString)"
        case .receipt(let id):
            return "receipt-\(id.uuidString)"
        }
    }
}
