import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            HomeView()
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            ShoppingListView()
                .tabItem { Label(AppTab.shopping.title, systemImage: AppTab.shopping.systemImage) }
                .tag(AppTab.shopping)

            InventoryView()
                .tabItem { Label(AppTab.inventory.title, systemImage: AppTab.inventory.systemImage) }
                .tag(AppTab.inventory)

            ReceiptView()
                .tabItem { Label(AppTab.receipt.title, systemImage: AppTab.receipt.systemImage) }
                .tag(AppTab.receipt)

            ConciergeView()
                .tabItem { Label(AppTab.concierge.title, systemImage: AppTab.concierge.systemImage) }
                .tag(AppTab.concierge)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .task {
            appState.bootstrapIfNeeded(modelContext: modelContext)
        }
        .sheet(isPresented: $state.isModelSetupPresented) {
            ModelDownloadView()
                .interactiveDismissDisabled(!appState.modelManager.isModelReady)
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.latestToast {
                Text(toast)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2))
                        appState.latestToast = nil
                    }
            }
        }
    }
}
