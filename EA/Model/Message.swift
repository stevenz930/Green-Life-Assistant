//
//  Message.swift
//  EA
//
//  Created by Steven Z on 2026/4/1.
//

import Foundation
import UIKit

struct Message: Identifiable {
    let id: UUID
    let content: String?
    let image: UIImage?
    let isUser: Bool
    let isThinking: Bool

    init(
        content: String?,
        image: UIImage? = nil,
        isUser: Bool,
        isThinking: Bool = false,
        id: UUID = UUID()
    ) {
        self.id = id
        self.content = content
        self.image = image
        self.isUser = isUser
        self.isThinking = isThinking
    }
}
