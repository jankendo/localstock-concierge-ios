import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.blue)
                    Text("Gemma 4 モデルを準備")
                        .font(.title2.weight(.bold))
                    Text("初回だけ Gemma 4 E2B-it の LiteRT-LM モデルを端末内 Documents に保存します。推論とレシート解析は端末内で実行します。")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    StatusPill(text: appState.modelManager.state.label, color: statusColor, systemImage: "arrow.down.circle")

                    if case .downloading(let progress) = appState.modelManager.state {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if case .failed(let message) = appState.modelManager.state {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()

                Button {
                    appState.modelManager.startInitialDownload()
                } label: {
                    Label(buttonTitle, systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading || appState.modelManager.isModelReady)

                Button("あとで設定から確認") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(isDownloading)
            }
            .padding()
            .navigationTitle("初回セットアップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appState.modelManager.isModelReady {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
        }
    }

    private var isDownloading: Bool {
        if case .downloading = appState.modelManager.state { return true }
        return false
    }

    private var buttonTitle: String {
        appState.modelManager.isModelReady ? "モデル準備完了" : "Gemma 4をダウンロード"
    }

    private var statusColor: Color {
        switch appState.modelManager.state {
        case .ready:
            return .green
        case .failed:
            return .red
        case .downloading:
            return .blue
        case .checking, .missing:
            return .orange
        }
    }
}
