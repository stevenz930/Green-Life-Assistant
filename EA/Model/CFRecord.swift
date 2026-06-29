//
//  CFRecord.swift
//  EA
//
//  Created by Steven Z on 2026/1/1.
//

// MARK: - Carbon Footprint Record Model
import Foundation

struct CFRecord: Codable, Identifiable {
    let id: Int?
    let user_id: Int
    let updated_at: String?
    let today_cf: Double
}
