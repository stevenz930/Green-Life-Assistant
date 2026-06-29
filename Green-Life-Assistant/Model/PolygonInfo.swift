//
//  PolygonInfo.swift
//  EA
//
//  Created by Steven Z on 2025/12/29.
//

// NOT USED

import Foundation

struct PolygonInfo: Codable {
    var id: Int
    let latitude, longitude: Double
    let BLDG_ENGNM: String

    enum CodingKeys: String, CodingKey {
        case id = "OBJECTID"
        case BLDG_ENGNM = "BLDG_ENGNM"
        case latitude = "latitude"
        case longitude = "longitude"
    }
}
