//
//  DashboardView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @State private var locationManager = LocationManager()
    
    @State private var points: [AnnotatedItem] = []
    @State private var overlays: [OverlayEntry] = []
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    private let defaultDistance: Double = 10000
    @State private var nowLocation: CLLocationCoordinate2D?
    @State private var nowDistance: Double = 10000
    @State private var nowHeading: Double = 0
    @State private var nowPitch: Double = 0
    
    @State private var route: MKRoute?
    @State private var walkingTimeDisplay: String = ""
    @State private var midpointCoordinate: CLLocationCoordinate2D?
    
    // 占位坐标
    let startCoord = CLLocationCoordinate2D(latitude: 22.2811711759, longitude: 114.2242716033)
    let endCoord = CLLocationCoordinate2D(latitude: 22.2822103178, longitude: 114.179171928)
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    // MARK: - Map View
                    Map(position: $cameraPosition) {
                        // markers
                        ForEach(points) { point in
                            Marker(point.name, coordinate: point.coordinate).tint(.green)
                        }
                        
                        // polygon overlays
                        ForEach(overlays) { entry in
                            MapPolygon(entry.polygon)
                                .foregroundStyle(.green.opacity(0.4))
                                .stroke(.green, lineWidth: 2)
                        }
                        
                        // 画出路径
                        if let route {
                            MapPolyline(route)
                                .stroke(.cyan, lineWidth: 9)
                            MapPolyline(route)
                                .stroke(.blue.opacity(0.8), lineWidth: 5)
                        }
                        
                        // 在路径中点显示时间标签
                        if let midpoint = midpointCoordinate, !walkingTimeDisplay.isEmpty {
                            Annotation("", coordinate: midpoint) {
                                Text(walkingTimeDisplay)
                                    .font(.caption2).bold()
                                    .padding(6)
                                    .foregroundColor(.white)
                                    .background(.blue)
                                    .clipShape(Capsule())
                                    .shadow(radius: 3)
                                    // 使用 overlay 增加一个小箭头指向路径
                                    .overlay(alignment: .bottom) {
                                        Image(systemName: "arrowtriangle.down.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.blue)
                                            .offset(y: 5)
                                    }
                                    .offset(y: -20)
                            }
                        }
                        
                    }
                    .mapControls {
                        MapUserLocationButton() // 系统自带的定位按钮
                    }
                    .onMapCameraChange(frequency: .continuous) { context in
                        // 实时更新当前中心点坐标信息
                        nowLocation = context.camera.centerCoordinate
                        nowDistance = context.camera.distance
                        nowHeading = context.camera.heading
                        nowPitch = context.camera.pitch
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                
                // MARK: - Zoom Button Group
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack {
                            // MARK: - Find nearby button
                            Button {
                                if let coord = locationManager.userLocation {
                                    nowLocation = coord
                                    fetchRoute()
                                }
                            } label: {
                                Image(systemName: "figure.walk")
                            }
                            .buttonStyle(.glass)
                            
                            
                            //  MARK: - Zoom In Button
                            Button {
                                nowDistance /= 3
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    cameraPosition = .camera(MapCamera(
                                        centerCoordinate: nowLocation!, // 使用最后记录的中心点
                                        distance: nowDistance,
                                        heading: nowHeading,
                                        pitch: nowPitch
                                    ))
                                }
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.glass)
                            
                            // MARK: - Zoom Out Button
                            Button {
                                nowDistance *= 3
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    cameraPosition = .camera(MapCamera(
                                        centerCoordinate: nowLocation!, // 使用最后记录的中心点
                                        distance: nowDistance,
                                        heading: nowHeading,
                                        pitch: nowPitch
                                    ))
                                }
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.glass)
                        }
                        .padding()
                    }
                }
            }
            .toolbar{
                // MARK: - Select Location Menu
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        ForEach(points) { point in
                            Button(point.name) {
                                //selectedPoint = point
                                nowLocation = point.coordinate
                                
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    cameraPosition = .camera(MapCamera(
                                        centerCoordinate: nowLocation!,
                                        distance: defaultDistance,
                                        heading: 0,
                                        pitch: 0
                                    ))
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        cameraPosition = .camera(MapCamera(
                                            centerCoordinate: nowLocation!,
                                            distance: defaultDistance / 10,
                                            heading: 0,
                                            pitch: 45
                                        ))
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "location.circle")
                    }
                }
                
                // MARK: - Reload GeoJSON Button
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        loadGeoJSON()
                        withAnimation(.easeInOut(duration: 0.5)) {
                            if let coord = locationManager.userLocation {
                                cameraPosition = .camera(MapCamera(
                                    centerCoordinate: coord,
                                    distance: defaultDistance,
                                    heading: 0,
                                    pitch: 0
                                ))
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            //.navigationTitle("Walking Time \(walkingTimeDisplay)")
        }
        // MARK: - On Appear & Task
        .onAppear {
            loadGeoJSON()
            nowLocation = points[0].coordinate
            cameraPosition = .camera(MapCamera(
                centerCoordinate: startCoord,
                distance: defaultDistance,
                heading: 0,
                pitch: 0
            ))
        }
        .task {
            await locationManager.requestLocation()
            if let coord = locationManager.userLocation {
                print("user location:", coord.latitude, coord.longitude)
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: coord,
                    distance: defaultDistance,
                    heading: 0,
                    pitch: 0
                ))
            }
        }
        
    }
    
    
    
    // MARK: - Functions
    
    
    
    // MARK: - Load and Parse GeoJSON
    func loadGeoJSON() {
        // Load GeoJSON data from the app bundle
        guard let url = Bundle.main.url(forResource: "RecyclingStations", withExtension: "geojson"),
              let data = try? Data(contentsOf: url) else { return }
        
        let decoder = MKGeoJSONDecoder()// Decode GeoJSON data
        guard let objects = try? decoder.decode(data) else { return }// Parse geometries and create overlay entries
        
        var newOverlays: [OverlayEntry] = []
        var newPoints: [AnnotatedItem] = []
        
        let needConvert = shouldConvertToGCJ02()// 判定是否需要转换坐标
        
        for object in objects {
            guard let feature = object as? MKGeoJSONFeature else { continue }
            
            let name = getName(feature)
            
            for geometry in feature.geometry {
                
                // MARK: - 单一 Polygon
                if let polygon = geometry as? MKPolygon {
                    let converted = convertPolygonIfNeeded(polygon, needConvert: needConvert)
                    newOverlays.append(OverlayEntry(polygon: converted))
                    
                    // 取第一个坐标， 生成 Marker
                    if let first = converted.coordinates.first {
                        newPoints.append(
                            AnnotatedItem(
                                name: name,
                                coordinate: first
                            )
                        )
                    }
                }
                
                // MARK: - MultiPolygon → 展开
                if let multiPolygon = geometry as? MKMultiPolygon {
                    
                    var isFirstPolygon = true
                    
                    for poly in multiPolygon.polygons {
                        let converted = convertPolygonIfNeeded(poly, needConvert: needConvert)
                        newOverlays.append(OverlayEntry(polygon: converted))
                        
                        // 只在第一个 polygon 生成 Marker
                        if isFirstPolygon, let first = converted.coordinates.first {
                            newPoints.append(AnnotatedItem(name: name, coordinate: first))
                            isFirstPolygon = false
                        }
                    }
                }
            }
        }
        
        overlays = newOverlays
        points = newPoints
    }
    
    // MARK: - Get Name from GeoJSON
    func getName(_ feature: MKGeoJSONFeature) -> String {
        // 解析属性字典，提取名称
        guard let props = feature.properties,
              let json = try? JSONSerialization.jsonObject(with: props) as? [String: Any] else {
            return "Polygon"
        }
        
        var name: String = "Polygon"
        if let languageCode = Locale.preferredLanguages.first {
            if languageCode.hasPrefix("zh") {
                name = json["BLDG_CHTNM"] as! String
            } else {
                name = json["BLDG_ENGNM"] as! String
            }
        }
        return name
    }
    
    // MARK: - Fetch Route between Two Coordinates
    func fetchRoute() {
        let request = MKDirections.Request()
        let needConvert = shouldConvertToGCJ02()// 判定是否需要转换坐标
        
        // 转换起点和终点坐标
        let startCoordConverted = convertCoordinateIfNeeded(startCoord, needConvert: needConvert)
        let endCoordConverted = convertCoordinateIfNeeded(endCoord, needConvert: needConvert)
        
        // 创建 CLLocation 对象
        var sourceLocation = CLLocation(latitude: startCoordConverted.latitude, longitude: startCoordConverted.longitude)
        var destinationLocation = CLLocation(latitude: endCoordConverted.latitude, longitude: endCoordConverted.longitude)
        
        // 如果有用户位置
        if let coord = locationManager.userLocation {
            // 以用户位置作为起点
            sourceLocation = CLLocation(
                latitude: convertCoordinateIfNeeded(coord, needConvert: needConvert).latitude,
                longitude: convertCoordinateIfNeeded(coord, needConvert: needConvert).longitude
            )
            
            // 以最近的位置为终点
            if let result = findNearestLocation(coord, points) {
                //print("最近的坐标是: \(result.coordinate)，距离: \(result.distance)米, 名字： \(result.name)")
                destinationLocation = CLLocation(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude)
            }
        }
        
        // 设置起点和终点
        request.source = MKMapItem(location: sourceLocation, address: nil)
        request.destination = MKMapItem(location: destinationLocation, address: nil)
        
        // 设置交通方式：.automobile (驾车), .walking (步行)
        request.transportType = .walking
        
        Task {
            let directions = MKDirections(request: request)
            do {
                let response = try await directions.calculate()
                // 获取返回结果中的第一条路线
                self.route = response.routes.first
                if let firstRoute = response.routes.first {
                    // 更新路线用于地图绘制
                    self.route = firstRoute
                    
                    // 获取并格式化步行时间
                    // expectedTravelTime 单位是秒
                    self.walkingTimeDisplay = formatTravelTime(firstRoute.expectedTravelTime)
                    
                    // 取路径坐标数组的中点
                    let pointCount = firstRoute.polyline.pointCount
                    let middlePoint = firstRoute.polyline.points()[pointCount / 2]
                    self.midpointCoordinate = middlePoint.coordinate
                }
            } catch {
                print("计算路径失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 时间格式化
    func formatTravelTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        // 根据系统语言自动显示 "12 minutes" 或 "12 分钟"
        //formatter.calendar?.locale = Locale.current
        //formatter.calendar?.locale = Locale.preferredLanguages.first.map { Locale(identifier: $0) }
        
        return formatter.string(from: seconds) ?? ""
    }
    
    // MARK: - Find Nearest Location
    // 找出坐标组中距离当前坐标最近的一个
    func findNearestLocation(_ currentUserLocation: CLLocationCoordinate2D, _ points: [AnnotatedItem]) -> (coordinate: CLLocationCoordinate2D, distance: CLLocationDistance, name: String)? {
        
        // 将当前坐标转换为 CLLocation 对象（用于计算距离）
        let current = CLLocation(latitude: currentUserLocation.latitude, longitude: currentUserLocation.longitude)
        
        // 使用 min(by:) 找出距离最小的项
        let nearest = points.min { (a, b) -> Bool in
            let distA = current.distance(from: CLLocation(
                latitude: a.coordinate.latitude,
                longitude: a.coordinate.longitude
            ))
            let distB = current.distance(from: CLLocation(
                latitude: b.coordinate.latitude,
                longitude: b.coordinate.longitude
            ))
            return distA < distB
        }
        
        // 返回结果
        if let nearest = nearest {
            let distance = current.distance(from: CLLocation(
                latitude: nearest.coordinate.latitude,
                longitude: nearest.coordinate.longitude
            ))
            return (nearest.coordinate, distance, nearest.name)
        }
        
        return nil
    }
    
}

#Preview {
    MapView()
}
