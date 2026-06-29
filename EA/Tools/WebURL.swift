//
//  WebURL.swift
//  EA
//
//  Created by Codex on 2026/04/21.
//

import Foundation

extension URL {
    var isSupportedWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

extension String {
    var normalizedWebURL: URL? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed), directURL.isSupportedWebURL {
            return directURL
        }

        if !trimmed.contains("://"), let urlWithScheme = URL(string: "https://\(trimmed)"), urlWithScheme.isSupportedWebURL {
            return urlWithScheme
        }

        return nil
    }
}
