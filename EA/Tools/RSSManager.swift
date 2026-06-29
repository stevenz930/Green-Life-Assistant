//
//  RSSManager.swift
//  EA
//
//  Created by Steven Z on 2026/04/31.
//

import Foundation
import Observation

@Observable
class RSSManager: NSObject {
    // 汇总所有源的新闻
    var allItems: [RSSItem] = []
    var isRefreshing = false

    // 使用 TaskGroup 并发解析多个 URL
    func fetchAllFeeds(feeds: [String: String]) async {
        isRefreshing = true
        
        await withTaskGroup(of: [RSSItem].self) { group in
            for (urlString, tag) in feeds {
                guard let url = URL(string: urlString) else { continue }
                
                group.addTask {
                    // 单个解析实例
                    let parser = await SingleFeedParser()
                    // 传入 tag
                    return await parser.parse(url: url, sourceTag: tag)
                }
            }
            
            // 收集所有解析结果
            var fetchedItems: [RSSItem] = []
            for await items in group {
                fetchedItems.append(contentsOf: items)
            }
            
            // 按日期排序并更新 UI
            await MainActor.run {
                self.allItems = fetchedItems.sorted { $0.pubDate > $1.pubDate }
                self.isRefreshing = false
            }
        }
    }
}


