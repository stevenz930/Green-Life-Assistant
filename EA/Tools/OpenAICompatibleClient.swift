//
//  OpenAICompatibleClient.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import Foundation
import OpenAI

// Stream Event Types
enum OpenAICompatibleStreamEvent {
    case delta(String)
    case reasoningDelta(String)
    case finished(responseID: String?, outputText: String?, reasoningText: String?)
}

// MARK: - OpenAI-Compatible Client
actor OpenAICompatibleClient {
    // Singleton
    static let shared = OpenAICompatibleClient()

    // Configuration And State
    private let openAIClient: OpenAIAsync
    private var activeStreamID: UUID?
    private var activeStreamTask: Task<Void, Never>?
    private var conversationMessages: [ChatQuery.ChatCompletionMessageParam] = []
    private var responseMessagesByID: [String: [ChatQuery.ChatCompletionMessageParam]] = [:]
    private var hasPerformedStartupHealthCheck = false
    private let debugLoggingEnabled = true
    private let configuredModelID: String
    private var resolvedModelID: String
    private let defaultModelID = "mimo-v2.5"
    private let systemPrompt = """
    # Role: 香港環保生活達人 (HK Eco-Expert)

    ## Profile
    你是一位熟悉香港垃圾分類及回收政策（如「綠在區區」網絡、四電一腦）的環保專家。你說話親切且實用，使用繁體中文（香港慣用語），旨在幫助香港市民減少使用預繳式垃圾袋，實踐低碳生活。

    ## Capabilities
    - **圖像識別**：當用戶上傳照片時，請精準辨識物品的材質（如 1號 PET 塑膠、紙類、金屬、或電子廢物）。
    - **本地知識**：提供符合香港環境保護署（EPD）指引的回收建議。

    ## Task
    1. **分類鑑定**：判斷物品屬於哪類回收物，並註明是否可交給「綠在區區」或「回收流動點」。
    2. **回收前處理**：教導用戶如何簡單清潔（如：撕掉包裝膠紙、沖洗殘餘食物）。
    3. **綠色重用 (Upcycling)**：提供 2 個適合香港狹小居住環境的舊物改造創意。
    4. **搵位回收**：提醒用戶尋找附近的回收點（如：綠在區區、智能回收桶）。

    ## Output Format
    請按以下結構回覆：
    ---
    📸 **物品辨識**：[描述照片中或文字提及的物品及其材質]
    ♻️ **香港回收指南**：
       - **類別**：[例如：塑膠、紙類、金屬、玻璃、電器]
       - **處理方式**：[例如：洗淨、剪碎、撕掉貼紙]
       - **去邊度回收**：[例如：綠在區區(可儲綠綠賞積分)、三色桶、智能回收機]
    🎨 **家居重用妙計**：
       - [方案一：考慮到香港家居空間細小，建議節省空間的用途]
       - [方案二：具創意的裝飾或功能性改造]
    💡 **環保冷知識**：[一個與該材質相關的香港環保數據或有趣事實]
    ---

    ## Constraints
    - 使用香港慣用語（如：膠樽、紙包飲品盒、綠在區區、綠綠賞）。
    - 若涉及大型電器，請提及「四電一腦」回收熱線。
    - 若物品不可回收，請誠實告知，並建議如何減少產生此類垃圾。
    """

    private struct StreamAccumulator {
        var responseID: String?
        var outputText: String = ""
        var reasoningText: String = ""
    }

    private init() {
        configuredModelID = defaultModelID
        resolvedModelID = defaultModelID
        let trimmedAPIKey = Config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration = OpenAI.Configuration(
            token: trimmedAPIKey,
            host: Config.openAIHost,
            port: 443,
            scheme: "https",
            basePath: Config.openAIBasePath,
            timeoutInterval: 600,
            customHeaders: [
                "x-api-key": trimmedAPIKey
            ],
            parsingOptions: .relaxed
        )
        openAIClient = OpenAI(configuration: configuration)
    }

    // MARK: - Public Streaming API
    func streamReply(
        input: String,
        imageData: Data? = nil,
        previousResponseID: String?
    ) -> AsyncThrowingStream<OpenAICompatibleStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamID = UUID()
            let streamTask = Task {
                do {
                    let modelID = try await self.fetchModelID()

                    var baseConversation: [ChatQuery.ChatCompletionMessageParam]
                    if let previousResponseID,
                       let restored = self.responseMessagesByID[previousResponseID] {
                        baseConversation = restored
                    } else if previousResponseID == nil {
                        baseConversation = []
                    } else {
                        baseConversation = self.conversationMessages
                    }

                    let userMessage = self.makeUserMessage(
                        input: input,
                        imageData: imageData
                    )
                    let systemMessage = self.makeSystemMessage(prompt: self.systemPrompt)

                    let query = ChatQuery(
                        messages: [systemMessage] + baseConversation + [userMessage],
                        model: modelID,
                        stream: true
                    )

                    let nonStreamResult = try await self.openAIClient.chats(
                        query: ChatQuery(
                            messages: [systemMessage] + baseConversation + [userMessage],
                            model: modelID,
                            stream: false
                        )
                    )

                    var accumulator = StreamAccumulator()
                    accumulator.responseID = nonStreamResult.id
                    if let firstChoice = nonStreamResult.choices.first {
                        if let text = firstChoice.message.content, !text.isEmpty {
                            accumulator.outputText = text
                            continuation.yield(.delta(text))
                        }
                        if let reasoning = firstChoice.message.reasoning, !reasoning.isEmpty {
                            accumulator.reasoningText = reasoning
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                    }

                    continuation.yield(
                        .finished(
                            responseID: accumulator.responseID,
                            outputText: accumulator.outputText.isEmpty ? nil : accumulator.outputText,
                            reasoningText: accumulator.reasoningText.isEmpty ? nil : accumulator.reasoningText
                        )
                    )

                    let assistantText = accumulator.outputText.isEmpty ? "No response." : accumulator.outputText
                    var updatedConversation = baseConversation
                    updatedConversation.append(userMessage)
                    updatedConversation.append(
                        .assistant(.init(content: .textContent(assistantText)))
                    )
                    self.conversationMessages = updatedConversation
                    if let responseID = accumulator.responseID, !responseID.isEmpty {
                        self.responseMessagesByID[responseID] = updatedConversation
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        self.debugLog("SSE stream cancelled")
                        continuation.finish()
                        self.clearActiveStream(id: streamID)
                        return
                    }
                    self.debugLog("SSE stream failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
                self.clearActiveStream(id: streamID)
            }

            Task {
                self.registerActiveStream(id: streamID, task: streamTask)
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
                Task {
                    await self.clearActiveStream(id: streamID)
                }
            }
        }
    }

    // MARK: - Public Control API
    func stopStreaming() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeStreamID = nil
        debugLog("Active stream stop requested")
    }

    // MARK: - Startup Health Check
    func runStartupHealthCheckIfNeeded() async throws {
        guard !hasPerformedStartupHealthCheck else { return }
        hasPerformedStartupHealthCheck = true
        let modelsResult = try await openAIClient.models()
        let availableModelIDs = modelsResult.data.map(\.id)

        guard !availableModelIDs.isEmpty else {
            throw OpenAICompatibleClientError.noModelAvailable
        }

        if availableModelIDs.contains(configuredModelID) {
            resolvedModelID = configuredModelID
            debugLog("Startup auth health check passed (/models); model: \(configuredModelID)")
            return
        }

        if let fallbackModelID = availableModelIDs.first {
            resolvedModelID = fallbackModelID
            debugLog("Configured model \(configuredModelID) not supported; fallback model: \(fallbackModelID)")
        }
    }

    // MARK: - Request Construction
    private func makeUserMessage(
        input: String,
        imageData: Data?
    ) -> ChatQuery.ChatCompletionMessageParam {
        if let imageData {
            return .user(
                .init(
                    content: .contentParts([
                        .text(.init(text: input)),
                        .image(.init(imageUrl: .init(imageData: imageData, detail: nil)))
                    ])
                )
            )
        }

        return .user(
            .init(content: .string(input))
        )
    }

    private func makeSystemMessage(prompt: String) -> ChatQuery.ChatCompletionMessageParam {
        .system(.init(content: .textContent(prompt)))
    }

    // MARK: - Model Selection
    private func fetchModelID() async throws -> String {
        if resolvedModelID.isEmpty {
            throw OpenAICompatibleClientError.modelIDNotConfigured
        }
        return resolvedModelID
    }

    // MARK: - Debug Logging
    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("[OpenAICompatibleClient] \(message)")
    }

    // MARK: - Active Stream Tracking
    private func registerActiveStream(id: UUID, task: Task<Void, Never>) {
        activeStreamTask?.cancel()
        activeStreamID = id
        activeStreamTask = task
    }

    private func clearActiveStream(id: UUID) {
        guard activeStreamID == id else { return }
        activeStreamTask = nil
        activeStreamID = nil
    }
}

// MARK: - Client Errors
enum OpenAICompatibleClientError: LocalizedError {
    case modelIDNotConfigured
    case noModelAvailable

    var errorDescription: String? {
        switch self {
        case .modelIDNotConfigured:
            return "No model ID configured for OpenAI-compatible endpoint."
        case .noModelAvailable:
            return "No model is available from OpenAI-compatible endpoint."
        }
    }
}
