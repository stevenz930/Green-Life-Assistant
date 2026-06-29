//
//  User.swift
//  EA
//
//  Created by Steven Z on 2026/1/1.
//

import Foundation

struct User: Codable, Identifiable {
    let id: Int?
    let username: String
    let password: String
    let total_cf: Double
}
