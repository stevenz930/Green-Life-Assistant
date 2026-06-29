//
//  RSSItem.swift
//  EA
//
//  Created by Steven Z on 2025/12/31.
//

import Foundation

struct RSSItem: Identifiable {
    let id = UUID()
    var title: String = ""
    var link: String = ""
    var description: String = ""
    var sourceTag: String = ""
    var pubDate: Date = Date()
}
