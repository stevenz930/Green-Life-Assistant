//
//  AQHI.swift
//  EA
//
//  Created by Steven Z on 2025/12/17.
//

// MARK: - AQHI Model
import Foundation
import SwiftUI

struct AQHI: Decodable, Identifiable {
    let id: Int?
    let type: String
    let aqhi_max: Double
    let health_risk_max: String
    let publish_date: Date
    
    var color: Color{
        switch health_risk_max {
        case "Low":
            return Color.green
        case "Moderate":
            return Color.yellow
        case "High":
            return Color.red
        case "Very High":
            return Color.brown
        case "Extreme":
            return Color.black
        default:
            return Color.green
        }
    }
}
