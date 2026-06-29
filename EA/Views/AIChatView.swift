//
//  AIChatView.swift
//  EA
//
//  Created by Steven Z on 2026/04/22.
//

import SwiftUI
import PhotosUI
import MarkdownUI
import Combine

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AIChatViewModel()
    
    private let bottomAnchorID = "CHAT_BOTTOM_ANCHOR"
    
    // PhotosPicker 選中的項目（用於載入圖片資料）
    @State private var selectedItem: PhotosPickerItem?
    
    // 建立聊天頁主畫面，包含訊息列表、錯誤提示與輸入區
    var body: some View {
        NavigationStack {
            VStack {
                chatListSection
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }
                composerSection
            }
            .navigationTitle("Assistant")
            // 當訊息數量改變時，將最新訊息陣列同步到 session 暫存
            .onChange(of: viewModel.messages.count) { _, _ in
                viewModel.syncSessionMessages()
            }
            // 串流內容刷新時，同步目前訊息內容（例如同一則訊息文字增量更新）
            .onChange(of: viewModel.streamUpdateTick) { _, _ in
                viewModel.syncSessionMessages()
            }
            // 當上一輪回應 ID 變更時，同步保存以維持多輪對話上下文
            .onChange(of: viewModel.previousResponseID) { _, _ in
                viewModel.syncSessionResponseID()
            }
            // 當使用者重新選取圖片時，讀取資源並更新預覽圖
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    await viewModel.updateSelectedImage(from: newItem)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.body)
                    }
                }
            }
        }
    }

    // MARK: - Build Chat List Section
    // 顯示聊天訊息清單，並在訊息更新時自動滾到最底部
    private var chatListSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack {
                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .padding(.horizontal)
                    }
                    if viewModel.isSending {
                        HStack {
                            ProgressView()
                                .padding(.leading)
                            if viewModel.isSending && !viewModel.hasStartedAssistantOutput {
                                Text("Prompt processing...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
            }
            // 新增或刪除訊息列時，自動捲到清單底部
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToAnchor(
                    using: proxy,
                    anchorID: bottomAnchorID,
                    animation: .easeOut(duration: 0.45)
                )
            }
            // 只在偵測到新行時觸發較平滑的自動捲動
            .onChange(of: viewModel.lineScrollTick) { _, _ in
                scrollToAnchor(
                    using: proxy,
                    anchorID: bottomAnchorID,
                    animation: .easeOut(duration: 0.45)
                )
            }
            // 送出狀態切換時（開始/結束），確保底部進度或最新訊息可見
            .onChange(of: viewModel.isSending) { _, _ in
                scrollToAnchor(
                    using: proxy,
                    anchorID: bottomAnchorID,
                    animation: .easeOut(duration: 0.45)
                )
            }
            // 清單首次出現時先還原 session，再定位到最新訊息底部
            .onAppear {
                viewModel.restoreSessionIfNeeded()
                scrollToAnchor(
                    using: proxy,
                    anchorID: bottomAnchorID,
                    animation: .easeOut(duration: 0.45)
                )
            }
        }
    }

    // MARK: - Build Single Message Row
    // 根據訊息角色（使用者或助手）組出單列訊息 UI
    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        HStack {
            if message.isUser {
                Spacer()
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(10)
                        .frame(maxWidth: 300, alignment: .trailing)
                }
            } else {
                if let content = message.content, !content.isEmpty {
                    Markdown(content)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        }
    }

    // MARK: - Build Composer Section
    // 建立輸入區，包含選圖按鈕、文字輸入與送出/停止按鈕
    private var composerSection: some View {
        HStack {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Image(systemName: "plus")
                    .font(.title)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            imagePickerPreview

            TextField("Type your message...", text: $viewModel.inputText)
                .textFieldStyle(.automatic)
                .onSubmit {
                    viewModel.sendMessage()
                }

            composerActionButton
        }
        .padding(.horizontal)
    }

    // MARK: - Build Image Preview Section
    // 顯示目前已選圖片縮圖，並提供一鍵清除
    private var imagePickerPreview: some View {
        ZStack(alignment: .topTrailing) {
            if let selectedImage = viewModel.selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    viewModel.selectedImage = nil
                    self.selectedItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .black.opacity(0.7))
                }
                .padding(2)
            } else {
                Color.clear
                    .frame(width: 1, height: 44)
            }
        }
    }

    // MARK: - Build Composer Action Button
    // 依目前狀態切換送出按鈕或停止按鈕
    private var composerActionButton: some View {
        Group {
            if viewModel.isSending {
                Button(action: {
                    viewModel.stopGenerating()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            } else {
                Button(action: {
                    viewModel.sendMessage()
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.title)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(
                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    viewModel.selectedImage == nil
                )
            }
        }
    }
    
    // MARK: - Scroll To Anchor
    // 封裝滾動邏輯，將指定錨點平滑捲動到可視區底部
    private func scrollToAnchor(using proxy: ScrollViewProxy, anchorID: String, animation: Animation) {
        DispatchQueue.main.async {
            withAnimation(animation) {
                proxy.scrollTo(anchorID, anchor: .bottom)
            }
        }
    }
}
