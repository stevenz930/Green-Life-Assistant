//
//  OverlayEntry.swift
//  EA
//
//  Created by Steven Z on 2025/12/30.
//

import Foundation
import MapKit

struct OverlayEntry: Identifiable {
    let id = UUID()
    let polygon: MKPolygon
}
