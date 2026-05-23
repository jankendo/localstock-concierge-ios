import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ReceiptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isProcessing = false
    @State private var rawText = ""
    @State private var candidates: [ReceiptCandidate] = []
    @State private var lastError: String?

    private let ocrService = VisionOCRService()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [StockTheme.lemon.opacity(0.16), StockTheme.softBackground, StockTheme.sky.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        captureControls

                        if isProcessing {
                            ProgressView("レシートを読み取り中")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                        }

                        if let lastError {
                            Text(lastError)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(12)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        if !candidates.isEmpty {
                            SectionHeader(title: "登録候補", systemImage: "checklist")
                            candidateList
                            Button {
                                Task {
                                    await registerSelectedCandidates()
                                }
                            } label: {
                                Label("選択したものを在庫に追加", systemImage: "shippingbox.and.arrow.backward.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if !rawText.isEmpty {
                            DisclosureGroup("OCRテキスト") {
                                Text(rawText)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                            .padding(12)
                            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("レシート")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isCameraPresented) {
                CameraCaptureView { image in
                    Task { await process(image: image) }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await loadPhoto(newValue) }
            }
        }
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(StockTheme.sky, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("レシート登録")
                        .font(.headline.weight(.black))
                    Text("候補を確認してから保存")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Button {
                    isCameraPresented = true
                } label: {
                    Label("撮影", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("写真", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var candidateList: some View {
        VStack(spacing: 10) {
            ForEach($candidates) { $candidate in
                Toggle(isOn: $candidate.isSelected) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.normalizedName)
                                .font(.headline)
                            Spacer()
                            Text("\(candidate.quantity.formattedStock)\(candidate.unit)")
                                .font(.subheadline.weight(.semibold))
                        }
                        HStack {
                            Text(candidate.rawName)
                            Spacer()
                            Text(candidate.price.map { "\($0)円" } ?? "")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        StatusPill(text: "\(Int(candidate.confidence * 100))%", color: candidate.confidence < 0.7 ? .orange : .green)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
            }
        }
    }

    private var repository: SwiftDataInventoryRepository {
        SwiftDataInventoryRepository(context: modelContext)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw OCRError.invalidImage
            }
            await process(image: image)
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func process(image: UIImage) async {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let result = try await ocrService.recognizeText(in: image)
            rawText = result.rawText
            let parse = await ReceiptParser.parse(rawText: result.rawText, llmService: appState.modelManager.makeLLMService())
            candidates = parse.items
            _ = try await appState.inventoryStore.saveReceipt(
                rawText: result.rawText,
                parsedJSON: parse.encodedJSON,
                storeName: parse.storeName,
                purchasedAt: parse.purchasedAt,
                totalAmount: parse.totalAmount,
                imageLocalPath: nil
            )
            if candidates.isEmpty {
                lastError = "在庫候補を確定できませんでした。手動で商品を追加してください。"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func registerSelectedCandidates() async {
        do {
            var count = 0
            for candidate in candidates where candidate.isSelected {
                let matches = try repository.searchProducts(query: candidate.normalizedName)
                let product: Product
                if let existing = matches.first {
                    product = existing
                } else {
                    product = try await appState.inventoryStore.createProduct(ProductDraft(
                        name: candidate.normalizedName,
                        category: candidate.category,
                        locationName: candidate.category.defaultLocationName,
                        unit: candidate.unit,
                        managementType: candidate.category == .food ? .cyclePrediction : .unopenedPackage,
                        minStock: 1,
                        idealStock: candidate.category == .food ? 1 : 2,
                        cycleDays: candidate.category == .food ? 7 : nil,
                        aliases: [candidate.rawName]
                    ))
                }
                _ = try await appState.inventoryStore.recordPurchase(
                    productId: product.id,
                    quantity: candidate.quantity,
                    unit: candidate.unit,
                    source: .ocrReceipt,
                    confidence: candidate.confidence,
                    note: "レシートOCR"
                )
                count += 1
            }
            appState.showToast("\(count)件を在庫に追加しました")
            candidates.removeAll()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.delegate = context.coordinator
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.allowsEditing = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private extension ProductCategory {
    var defaultLocationName: String {
        switch self {
        case .dailyGoods:
            return "日用品収納"
        case .laundry:
            return "洗面所"
        case .bath:
            return "浴室収納"
        case .kitchen:
            return "キッチン"
        case .food:
            return "冷蔵庫"
        case .medicine:
            return "薬箱"
        case .storage:
            return "収納"
        case .other:
            return "未設定"
        }
    }
}
