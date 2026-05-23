import Foundation

#if canImport(CoreNFC)
import CoreNFC

@MainActor
final class NFCService: NSObject, NFCNDEFReaderSessionDelegate {
    private var session: NFCNDEFReaderSession?
    var onURI: ((URL) -> Void)?
    var onMessage: ((String) -> Void)?

    func beginScan() {
        guard NFCNDEFReaderSession.readingAvailable else {
            onMessage?("この端末ではNFC読み取りを利用できません。")
            return
        }
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "収納タグまたは商品タグをかざしてください。"
        session?.begin()
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.onMessage?(error.localizedDescription)
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let urls = messages
            .flatMap(\.records)
            .compactMap { record -> URL? in
                if let payload = String(data: record.payload, encoding: .utf8),
                   let url = URL(string: payload.trimmingCharacters(in: .controlCharacters)) {
                    return url
                }
                return record.wellKnownTypeURIPayload()
            }

        Task { @MainActor in
            if let url = urls.first {
                self.onURI?(url)
            } else {
                self.onMessage?("NFCタグからURLを読み取れませんでした。")
            }
        }
    }
}
#else
@MainActor
final class NFCService {
    var onURI: ((URL) -> Void)?
    var onMessage: ((String) -> Void)?

    func beginScan() {
        onMessage?("この環境ではNFCを利用できません。")
    }
}
#endif
