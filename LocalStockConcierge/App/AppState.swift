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

    private var hasBootstrapped = false

    func bootstrapIfNeeded(modelContext: ModelContext) {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        SeedData.ensureSeeded(in: modelContext)
        modelManager.refreshState()
        isModelSetupPresented = !modelManager.isModelReady
        notificationService.requestAuthorizationIfNeeded()
    }

    func showToast(_ message: String) {
        latestToast = message
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
