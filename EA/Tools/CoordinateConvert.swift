//
//  MKPolygon+Coordinates.swift
//  EA
//
//  Created by Steven Z on 2026/04/29.
//

import Foundation
import MapKit

// MARK: - 判定是否需要转换坐标
func shouldConvertToGCJ02() -> Bool {
    Locale.current.region?.identifier == "CN"
}

// MARK: - WGS-84 转 GCJ-02
func wgs84ToGcj02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    let a = 6378245.0
    let ee = 0.00669342162296594323
    
    let lat = coordinate.latitude
    let lon = coordinate.longitude
    
    let dLat = transformLat(lon - 105.0, lat - 35.0)
    let dLon = transformLon(lon - 105.0, lat - 35.0)
    
    let radLat = lat / 180.0 * .pi
    var magic = sin(radLat)
    magic = 1 - ee * magic * magic
    let sqrtMagic = sqrt(magic)
    
    let mgLat = lat + (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
    let mgLon = lon + (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
    
    return CLLocationCoordinate2D(latitude: mgLat, longitude: mgLon)
}

// MARK: - 坐标转换辅助函数
private func transformLat(_ x: Double, _ y: Double) -> Double {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
    ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
    ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
    ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
    return ret
}

private func transformLon(_ x: Double, _ y: Double) -> Double {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
    ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
    ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
    ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
    return ret
}

// MARK: - 转换坐标
func convertCoordinateIfNeeded(_ coordinate: CLLocationCoordinate2D, needConvert: Bool) -> CLLocationCoordinate2D {
    guard needConvert else { return coordinate }
    return wgs84ToGcj02(coordinate)
}

// MARK: - 转换 MKPolygon 坐标
func convertPolygonIfNeeded(_ polygon: MKPolygon, needConvert: Bool) -> MKPolygon {
    guard needConvert else { return polygon }
    
    let convertedCoords = polygon.coordinates.map { wgs84ToGcj02($0) }
    return MKPolygon(coordinates: convertedCoords, count: convertedCoords.count)
}

// MARK: - MKPolygon 扩展，获取坐标数组
extension MKPolygon {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: self.pointCount)
        self.getCoordinates(&coords, range: NSRange(location: 0, length: self.pointCount))
        return coords
    }
}
