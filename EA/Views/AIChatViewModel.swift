//
//  AIChatViewModel.swift
//  EA
//
//  Created by Steven Z on 2026/04/22.
//

import SwiftUI
import PhotosUI
import UIKit
import Combine

@MainActor
final class AIChatViewModel: ObservableObject {
    
    @Published var selectedImage: UIImage?
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    
    // 上一輪回應 ID（延續對話脈絡）
    @Published var previousResponseID: String?
    // 已展開的 thinking 訊息集合
    @Published var expandedThinkingMessageIDs: Set<UUID> = []
    // 目前活躍 thinking 訊息 ID
    @Published var activeThinkingMessageID: UUID?
    // 目前 thinking 開始時間
    @Published var activeThinkingStartedAt: Date?
    // 每則 thinking 訊息對應的累計秒數
    @Published var thinkingElapsedSecondsByMessageID: [UUID: Int] = [:]
    // 每則 thinking 訊息的收合預覽內容
    @Published var collapsedThinkingPreviewByMessageID: [UUID: String] = [:]
    // 串流更新節拍（驅動畫面刷新）
    @Published var streamUpdateTick: Int = 0
    // 行級捲動節拍（避免字級捲動過於頻繁）
    @Published var lineScrollTick: Int = 0
    // 助手是否已開始輸出可見內容
    @Published var hasStartedAssistantOutput: Bool = false
    
    @Published var messages: [Message] = []

    // 目前活躍中的串流任務
    private var chatStreamTask: Task<Void, Never>?
    // 避免重複還原 session 的旗標
    private var didRestoreSession: Bool = false

    // 管理單次串流過程中暫存的文字與 thinking 狀態
    private struct StreamHandlingState {
        // 助手正文累積內容
        var streamedText: String = ""
        // reasoning 累積內容
        var streamedReasoning: String = ""
        // 本輪對應的 thinking 訊息 ID
        var thinkingID: UUID?
    }

    // 將最新 messages 同步回執行期 session 暫存
    func syncSessionMessages() {
        AIChatSessionStore.shared.messages = messages
    }

    // 將上一輪回應 ID 同步回 session 暫存
    func syncSessionResponseID() {
        AIChatSessionStore.shared.previousResponseID = previousResponseID
    }

    // MARK: - UI State Updates
    // 每秒更新目前 thinking 已經過秒數
    func tickThinkingElapsed() {
        guard
            isSending,
            let thinkingID = activeThinkingMessageID,
            let startedAt = activeThinkingStartedAt
        else {
            return
        }
        thinkingElapsedSecondsByMessageID[thinkingID] = max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    // 載入使用者選取圖片，供輸入區預覽與後續送出
    func updateSelectedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage = image
        }
    }

    // MARK: - Conversation Flow
    // 驗證輸入後送出請求，並開始接收串流事件
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = selectedImage?.jpegData(compressionQuality: 0.82) ?? selectedImage?.pngData()
        guard (!text.isEmpty || imageData != nil), !isSending else { return }

        let assistantID = prepareForSending(text: text, imageForMessage: selectedImage)
        chatStreamTask = Task {
            do {
                let requestInput = text.isEmpty ? "Please describe this image." : text
                let stream = await OpenAICompatibleClient.shared.streamReply(
                    input: requestInput,
                    imageData: imageData,
                    previousResponseID: previousResponseID
                )
                var state = StreamHandlingState()

                for try await event in stream {
                    await MainActor.run {
                        self.handleStreamEvent(event, assistantID: assistantID, state: &state)
                    }
                }

                await MainActor.run {
                    self.completeStreaming(error: nil, assistantID: assistantID)
                }
            } catch {
                await MainActor.run {
                    self.completeStreaming(error: error, assistantID: assistantID)
                }
            }
        }
    }

    // 主動中止目前回覆，並要求底層停止串流
    func stopGenerating() {
        guard isSending else { return }
        chatStreamTask?.cancel()
        chatStreamTask = nil
        Task {
            await OpenAICompatibleClient.shared.stopStreaming()
        }
        finalizeThinkingTracking()
        isSending = false
        hasStartedAssistantOutput = false
    }

    // MARK: - Session Restore
    // 視圖首次出現時還原暫存內容
    func restoreSessionIfNeeded() {
        guard !didRestoreSession else { return }
        didRestoreSession = true

        messages = AIChatSessionStore.shared.messages
        previousResponseID = AIChatSessionStore.shared.previousResponseID

        if messages.isEmpty {
            messages = [
                Message(content: "Hi! Ask me anything about reducing carbon footprint.", isUser: false)
            ]
        }

        Task {
            do {
                try await OpenAICompatibleClient.shared.runStartupHealthCheckIfNeeded()
            } catch {
                await MainActor.run {
                    self.errorMessage = "OpenAI-compatible auth check failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Text Processing Utilities
    // 取出 thinking 最後三行作為收合預覽
    func latestThinkingPreview(from raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "Thinking...\n", with: "")
        let lines = cleaned
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "Thinking..." }
        let previewLines = Array(lines.suffix(3))
        return previewLines.joined(separator: "\n")
    }

    // MARK: - Pre-send Preparation
    // 送出前統一重置輸入狀態，並插入佔位訊息
    private func prepareForSending(text: String, imageForMessage: UIImage?) -> UUID? {
        let messageText: String? = text.isEmpty ? nil : text
        inputText = ""
        selectedImage = nil
        errorMessage = nil
        isSending = true
        hasStartedAssistantOutput = false
        activeThinkingMessageID = nil
        activeThinkingStartedAt = nil
        messages.append(Message(content: messageText, image: imageForMessage, isUser: true))
        messages.append(Message(content: "", isUser: false))
        return messages.last?.id
    }

    // MARK: - Stream Event Handling
    // 統一處理串流事件：正文、thinking、結束
    private func handleStreamEvent(
        _ event: OpenAICompatibleStreamEvent,
        assistantID: UUID?,
        state: inout StreamHandlingState
    ) {
        switch event {
        case .delta(let chunk):
            state.streamedText += chunk
            guard let assistantID,
                  let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            messages[idx] = Message(content: state.streamedText, isUser: false, id: assistantID)
            hasStartedAssistantOutput = true
            streamUpdateTick += 1
            if chunk.contains("\n") || chunk.contains("\r") {
                lineScrollTick += 1
            }

        case .reasoningDelta(let chunk):
            state.streamedReasoning += chunk

        case .finished(let responseID, let outputText, let reasoningText):
            if let responseID, !responseID.isEmpty {
                previousResponseID = responseID
            }

            if let reasoningText, !reasoningText.isEmpty, state.streamedReasoning.isEmpty {
                state.streamedReasoning = reasoningText
            }

            if let outputText, !outputText.isEmpty, state.streamedText.isEmpty {
                state.streamedText = outputText
                hasStartedAssistantOutput = true
            }

            guard let assistantID,
                  let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            let finalText = state.streamedText.isEmpty ? "No response." : state.streamedText
            messages[idx] = Message(content: finalText, isUser: false, id: assistantID)
            streamUpdateTick += 1
            lineScrollTick += 1
        }
    }

    // MARK: - Stream Finalization
    // 串流完成後做收尾與錯誤回填
    private func completeStreaming(error: Error?, assistantID: UUID?) {
        if let error, !(error is CancellationError) {
            let hasAssistantContent: Bool = {
                guard let assistantID,
                      let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return false }
                return !(messages[idx].content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }()

            if !hasAssistantContent {
                errorMessage = "OpenAI-compatible request failed: \(error.localizedDescription)"
            }
            if let assistantID,
               let idx = messages.firstIndex(where: { $0.id == assistantID }),
               (messages[idx].content ?? "").isEmpty {
                messages[idx] = Message(content: "Request failed.", isUser: false, id: assistantID)
            }
        }

        finalizeThinkingTracking()
        isSending = false
        hasStartedAssistantOutput = false
        chatStreamTask = nil
    }

    // MARK: - Thinking Timer Cleanup
    // 結束 thinking 計時並清理活躍追蹤
    private func finalizeThinkingTracking() {
        guard
            let thinkingID = activeThinkingMessageID,
            let startedAt = activeThinkingStartedAt
        else {
            return
        }
        thinkingElapsedSecondsByMessageID[thinkingID] = max(0, Int(Date().timeIntervalSince(startedAt)))
        expandedThinkingMessageIDs.remove(thinkingID)
        activeThinkingMessageID = nil
        activeThinkingStartedAt = nil
    }
}
