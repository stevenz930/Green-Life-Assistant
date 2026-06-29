//
//  AIChatSessionStore.swift
//  EA
//
//  Created by Steven Z on 2026/04/22.
//

import Foundation

// 儲存聊天視圖的執行期暫存資料（App 不重啟時可復用）。
final class AIChatSessionStore {
    // 全域唯一共享實例。
    static let shared = AIChatSessionStore()

    // 暫存聊天訊息列表。
    var messages: [Message] = [
        Message(content: "Hi! Ask me anything about reducing carbon footprint.", isUser: false)
    ]
    // 暫存上一輪回應 ID，用於串接多輪上下文。
    var previousResponseID: String?

    // 限制外部建立，確保使用單例。
    private init() {}
}
