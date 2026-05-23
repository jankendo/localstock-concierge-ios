import Foundation
import Observation

@MainActor
@Observable
final class GemmaModelManager {
    enum DownloadState: Equatable {
        case checking
        case missing
        case downloading(progress: Double)
        case ready(URL)
        case failed(String)

        var label: String {
            switch self {
            case .checking:
                return "確認中"
            case .missing:
                return "未取得"
            case .downloading(let progress):
                return "ダウンロード中 \(Int(progress * 100))%"
            case .ready:
                return "準備完了"
            case .failed:
                return "失敗"
            }
        }
    }

    static let modelFileName = "gemma-4-E2B-it.litertlm"
    static let modelSourceURL = URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true")!

    private let downloadClient = ModelDownloadClient()
    var state: DownloadState = .checking

    var localModelURL: URL {
        let modelsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        return modelsDirectory.appendingPathComponent(Self.modelFileName)
    }

    var isModelReady: Bool {
        if case .ready = state { return true }
        return FileManager.default.fileExists(atPath: localModelURL.path)
    }

    func refreshState() {
        if FileManager.default.fileExists(atPath: localModelURL.path) {
            state = .ready(localModelURL)
        } else {
            state = .missing
        }
    }

    func startInitialDownload() {
        guard case .downloading = state else {
            Task { await downloadModel() }
            return
        }
    }

    func makeLLMService() -> (any LocalLLMService)? {
        guard isModelReady else { return nil }
        return LiteRTGemmaLLMService(modelURL: localModelURL)
    }

    private func downloadModel() async {
        state = .downloading(progress: 0)
        do {
            let downloadedURL = try await downloadClient.download(
                from: Self.modelSourceURL,
                to: localModelURL,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        self?.state = .downloading(progress: progress)
                    }
                }
            )
            state = .ready(downloadedURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

final class ModelDownloadClient: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destinationURL: URL?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var session: URLSession?

    func download(from source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.destinationURL = destination
            self.progressHandler = progress
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 60 * 4
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: source).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationURL else {
            complete(with: .failure(ModelDownloadError.missingDestination))
            return
        }

        if let response = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            complete(with: .failure(ModelDownloadError.badStatus(response.statusCode)))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            complete(with: .success(destinationURL))
        } catch {
            complete(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    private func complete(with result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.destinationURL = nil
        self.progressHandler = nil
        session?.invalidateAndCancel()
        session = nil

        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

enum ModelDownloadError: LocalizedError {
    case missingDestination
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingDestination:
            return "モデル保存先が見つかりません。"
        case .badStatus(let code):
            return "モデル配布元がHTTP \(code)を返しました。"
        }
    }
}
