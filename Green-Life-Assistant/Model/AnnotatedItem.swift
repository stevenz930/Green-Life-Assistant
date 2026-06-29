//
//  AnnotatedItem.swift
//  EA
//
//  Created by Steven Z on 2025/12/28.
//

import Foundation
import MapKit

struct AnnotatedItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D

    // 判断两个 AnnotatedItem 是否相等
    // 基于 id 属性进行比较
    // 调用时触发
    static func == (lhs: AnnotatedItem, rhs: AnnotatedItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // 为 AnnotatedItem 生成hash
    // 基于 id 属性进行hash
    // 触发时间：当 AnnotatedItem 被用作hash表的键时
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
