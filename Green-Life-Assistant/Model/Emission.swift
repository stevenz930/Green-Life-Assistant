//
//  Emission.swift
//  EA
//
//  Created by Steven Z on 2025/12/18.
//

import Foundation

struct Emission: Identifiable {
    let id = UUID()
    let name: String
    let unit: String
    let factor: Double   // kg CO₂e per unit
    var input: String = ""
}
