//
//  SingleFeedParser.swift
//  EA
//
//  Created by Steven Z on 2026/04/31.
//

import Foundation
import Observation

@Observable
class SingleFeedParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentTag = ""
    private var currentPubDateString = ""
    
    // 解析
    func fetchAndParse(url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parser = XMLParser(data: data)
            parser.delegate = self
            // 重置数据
            self.items = []
            parser.parse()
        } catch {
            print("RSS 下载失败: \(error)")
        }
    }
    
    // MARK: - XMLParserDelegate
    
    func parse(url: URL, sourceTag: String) async -> [RSSItem] {
        self.currentTag = sourceTag // 记录标签
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        // 如果 <time> 标签有 datetime 属性，直接作为 pubDate 使用
        if currentElement == "time", let isoDate = attributeDict["datetime"] {
            currentPubDateString = isoDate
        }
        
        if currentElement == "item" {
            currentTitle = ""; currentLink = ""; currentPubDateString = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // 拼接字符，处理 XML 分段读取的情况
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "description": currentDescription += string
        case "pubDate": currentPubDateString += string
        default: break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceTag: self.currentTag, // 将标签注入每一个 Item
                pubDate: convertToDate(currentPubDateString)
            )
            items.append(item)
        }
    }
    
    // MARK: - 日期字符串转换
    // 辅助：解析不同格式的字符串
    private func convertToDate(_ dateString: String) -> Date {
        // 去除多余空格和换行
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Input Date String: [\(dateString)]")
        if trimmed.isEmpty { return Date() }

        // 尝试解析 ISO8601 (针对情况1: 2025-12-26T12:00:00Z)
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: trimmed) { return date }// 直接返回解析结果

        // 尝试解析标准 RSS (RFC822) 格式 (针对情况2: Tue, 30 Dec 2025 12:00:40 +0000)
        let rfcFormatter = DateFormatter()
        rfcFormatter.locale = Locale(identifier: "en_US_POSIX") // 必须固定
        rfcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // 常见的格式数组
        let formats = [
            "E, d MMM yyyy HH:mm:ss Z", // 标准
            "E, d MMM yyyy HH:mm:ss z", // 带时区缩写
            "E, d MMM yyyy HH:mm Z",    // 无秒
            "EEEE, MMMM d, yyyy - HH:mm" // 针对情况1
        ]
        
        // 格式化尝试
        for format in formats {
            rfcFormatter.dateFormat = format// 设置当前格式
            if let date = rfcFormatter.date(from: trimmed) {// 尝试解析
                return date// 返回解析结果
            }
        }

        // 所有格式都失败，返回当前日期并打印警告
        print("⚠️ 无法解析日期字符串: [\(trimmed)]")
        return Date()
    }
}
