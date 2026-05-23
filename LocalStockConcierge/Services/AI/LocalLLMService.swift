import Foundation

enum LLMMode: String, Sendable {
    case fastParse
    case chat
    case toolDecide
    case summary

    var maxTokens: Int {
        switch self {
        case .fastParse:
            return 512
        case .chat:
            return 1024
        case .toolDecide:
            return 256
        case .summary:
            return 512
        }
    }
}

protocol LocalLLMService: Sendable {
    func generate(prompt: String, mode: LLMMode) async throws -> String
}

actor LLMInferenceQueue {
    private let service: any LocalLLMService

    init(service: any LocalLLMService) {
        self.service = service
    }

    func enqueue(prompt: String, mode: LLMMode) async throws -> String {
        try await service.generate(prompt: prompt, mode: mode)
    }
}

enum LLMServiceError: LocalizedError {
    case modelMissing
    case runtimeUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Gemmaモデルがまだ端末内にありません。"
        case .runtimeUnavailable:
            return "LiteRT-LMランタイムを初期化できませんでした。"
        case .emptyResponse:
            return "モデルの応答が空でした。"
        }
    }
}

enum LLMPrompts {
    static func systemPrompt(for mode: LLMMode) -> String {
        switch mode {
        case .fastParse:
            return receiptSystemPrompt
        case .chat, .toolDecide, .summary:
            return conciergeSystemPrompt
        }
    }

    static let conciergeSystemPrompt = """
    あなたは家庭の在庫管理コンシェルジュです。
    ユーザーの目的は、買い忘れ・重複購入・在庫切れを防ぐことです。
    事実はローカルDBの内容を優先し、不明な在庫は断定しないでください。
    DB更新が必要な場合はJSON tool_callsだけを返し、confirm_requiredが必要な操作はtrueにしてください。
    勝手に削除しないでください。自然文回答は日本語で簡潔にしてください。
    """

    static let receiptSystemPrompt = """
    あなたは日本のレシート解析エンジンです。
    OCR文字列から家庭の在庫管理に関係する商品だけを抽出してください。
    食品、日用品、洗剤、消耗品、調味料、生活雑貨を対象にし、小計、合計、税、ポイント、決済情報は除外します。
    出力はJSONのみ。store_name, purchased_at, itemsを返してください。
    """
}
