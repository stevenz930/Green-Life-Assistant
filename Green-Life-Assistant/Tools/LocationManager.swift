//
//  LocationManager.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import CoreLocation
import Observation

@Observable
class LocationManager {
    private let manager = CLLocationManager()
    var userLocation: CLLocationCoordinate2D?
    
    func requestLocation() async {
        // 请求权限
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        
        // 获取位置更新
        do {
            let updates = CLLocationUpdate.liveUpdates()
            for try await update in updates {
                if let location = update.location {
                    self.userLocation = location.coordinate
                    // 只需要获取一次
                    break
                }
            }
        } catch {
            print("get location error: \(error)")
        }
    }
}

