import Foundation

#if canImport(LiteRTLM)
import LiteRTLM
#endif

actor LiteRTGemmaLLMService: LocalLLMService {
    private let modelURL: URL

    #if canImport(LiteRTLM)
    private var engine: Engine?
    #endif

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func generate(prompt: String, mode: LLMMode) async throws -> String {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LLMServiceError.modelMissing
        }

        #if canImport(LiteRTLM)
        let engine = try await preparedEngine(maxTokens: mode.maxTokens)
        let sampler = try SamplerConfig(topK: 40, topP: 0.95, temperature: mode == .fastParse ? 0.1 : 0.7)
        let config = ConversationConfig(
            systemMessage: Message(LLMPrompts.systemPrompt(for: mode), role: .system),
            samplerConfig: sampler
        )
        let conversation = try await engine.createConversation(with: config)
        let response = try await conversation.sendMessage(Message(prompt))
        let output = response.toString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw LLMServiceError.emptyResponse }
        return output
        #else
        throw LLMServiceError.runtimeUnavailable
        #endif
    }

    #if canImport(LiteRTLM)
    private func preparedEngine(maxTokens: Int) async throws -> Engine {
        if let engine {
            return engine
        }

        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiteRTLM", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let config = try EngineConfig(
            modelPath: modelURL.path,
            backend: .gpu,
            maxNumTokens: maxTokens,
            cacheDir: cacheURL.path
        )
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        self.engine = engine
        return engine
    }
    #endif
}
