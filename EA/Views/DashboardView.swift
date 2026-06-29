//
//  MapView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI

struct DashboardView: View {
    @State private var scrollID: Int? = 0
    @State private var scrollOffsetY: CGFloat = 0.0
    @State private var fileNames: [String] = [
        "Stream",
        "Sky",
        "WindTurbine"
    ]
    
    var body: some View {
        GeometryReader { geo in
            ZStack(){
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(fileNames.indices, id: \.self) { i in
                            ZStack{
                                // MARK: - Video Background
                                SingleVideoPlayerView(fileName: fileNames[i]).id(fileNames[i])
                                
                                
                                // MARK: - Overlay Content
                                switch i {
                                case 0:
                                    todayCFView()
                                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                                        .padding()
                                case 1:
                                    todayAQHIView()
                                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                                        .padding()
                                case 2:
                                    totalRecyclingCO2SavingsView()
                                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                                        .padding()
                                default: Text("")
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scrollTargetLayout()
                            .scrollTransition(.animated(.easeInOut(duration: 0.1))) { content, phase in
                                content
                                    .opacity(1 - abs(phase.value))
                                    .scaleEffect(1 - abs(phase.value) * 0.1)
                                    .blur(radius: abs(phase.value) * 5)
                            }
                            .id(i)
                        }
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newValue in
                    scrollOffsetY = newValue
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollID)
                
                // MARK: - Scroll to Top Button
                if scrollOffsetY >= geo.size.height*2/3 {
                    let isPad = UIDevice.current.userInterfaceIdiom == .pad
                    let x = isPad ? geo.size.width - (geo.size.width/14) : geo.size.width - (geo.size.width/8)
                    let y = geo.size.height - (geo.size.height/22)*4
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollID = 0   //  jump to the top item
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .shadow(radius: 5)
                    }
                    .position(x:x, y:y)
                    .opacity(scrollOffsetY >= geo.size.height ? 0.75 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: scrollOffsetY)
                }
                
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Today Carbon Footprint View
struct todayCFView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(TodayCFManager.self) private var todayCFManager
    
    @State private var todayCF: Double = 1145141.919810 //人一生大概排放 1200 吨
    
    func formatEmission(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2f", value / 1000)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    func formatEmissionUnit(_ value: Double) -> String {
        if value >= 1000 {
            return "Tons  CO₂e"
        } else {
            return "kg  CO₂e"
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            VStack{
                // MARK: - Title
                Text("\n")
                    .font(.title).bold().foregroundColor(.white).frame(maxWidth: .infinity)
                Text("Today's")
                    .font(.custom("Oswald", size: geo.size.height * 1/12, relativeTo: .largeTitle))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                Text("Carbon Footprint")
                    .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                // MARK: - Carbon Footprint Visualization
                Text(formatEmission(todayCFManager.todayCF))
                    .font(.custom("Oswald", size: geo.size.height * 1/3)).fontWeight(.ultraLight)
                    .lineLimit(1) // 限制为一行
                    .minimumScaleFactor(0.3)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                Text(formatEmissionUnit(todayCFManager.todayCF))
                    .font(.custom("Oswald", size: geo.size.height * 1/20)).fontWeight(.ultraLight)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                Spacer()
                Spacer()
            }
        }
        .task {
            do {
                if let userId = authManager.currentUser?.id {
                    todayCFManager.todayCF = try await fetchLatestTodayCF(userID: userId)
                }
            } catch {
                print("获取数据失败: \(error)")
            }
        }
        .background(Color.black.opacity(0.2).blur(radius: 10))
    }
}

// MARK: - Today AQHI View
struct todayAQHIView: View {
    @Environment(\.displayScale) var displayScale
    
    @State private var generalItem: AQHI?
    @State private var roadsideItem: AQHI?
    @State private var aqhiInfo: [AQHI] = []
    @State private var angle: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var selectedType: Int = 0
    
    @State private var offsetXB: CGFloat = 20
    @State private var offsetYB: CGFloat = -10
    @State private var offsetXF: CGFloat = 0
    @State private var offsetYF: CGFloat = -0
    
    var body: some View {
        GeometryReader { geo in
            VStack{
                // MARK: - Title
                Text("\n")
                    .font(.title).bold().foregroundColor(.white).frame(maxWidth: .infinity)
                Text("Today's")
                    .font(.custom("Oswald", size: geo.size.height * 1/13, relativeTo: .largeTitle))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                Text("Air Quality Health Index")
                    .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                
                // MARK: - Type Selection Button
                Button(action:{
                    if selectedType == 0{
                        selectedType = 1
                    } else if selectedType == 1{
                        selectedType = 0
                    }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        offsetXB = 0
                        offsetYB = 0
                        offsetXF = 20
                        offsetYF = -10
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            offsetXB = 20
                            offsetYB = -10
                            offsetXF = 0
                            offsetYF = 0
                        }
                    }
                }){
                    if selectedType == 0{
                        ZStack{
                            Text("Roadside")
                                .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                                .foregroundColor(.white.opacity(0.2))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            //.offset(x: 20, y: -10)
                                .offset(x: offsetXB, y: offsetYB)
                            Text("General")
                                .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .offset(x: offsetXF, y: offsetYF)
                        }
                    } else if selectedType == 1{
                        ZStack{
                            Text("General")
                                .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                                .foregroundColor(.white.opacity(0.2))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            //.offset(x: 20, y: -10)
                                .offset(x: offsetXB, y: offsetYB)
                            Text("Roadside")
                                .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .offset(x: offsetXF, y: offsetYF)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                
                // MARK: - AQHI Circle Visualization
                ZStack{
                    Text(selectedType == 0 ?
                         (generalItem?.aqhi_max != nil ? String(format: "%.0f", generalItem!.aqhi_max) : "1") :
                            (roadsideItem?.aqhi_max != nil ? String(format: "%.0f", roadsideItem!.aqhi_max) : "1")
                    )
                    .font(.custom("Oswald", size: geo.size.height * 2/5)).fontWeight(.ultraLight)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .opacity(0.3)
                    .offset(y: -geo.size.height * 0.02)
                    
                    // MARK: - Clipping Rotating Arc
                    Circle()
                        .trim(from: 0.0, to: 0.2)
                        .stroke(selectedType == 0 ?
                                (generalItem?.color.opacity(0.9) ?? .green.opacity(0.9)) :
                                    (roadsideItem?.color.opacity(0.9) ?? .green.opacity(0.9)),
                                style: StrokeStyle(
                                    lineWidth: geo.size.height * 0.01,
                                    lineCap: .round
                                )
                        )
                        .rotationEffect(.degrees(angle))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .onAppear {
                            withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: false)) {
                                angle = 360
                            }
                        }
                    
                    // MARK: - Circle
                    Circle()
                        .stroke(selectedType == 0 ?
                                (generalItem?.color.opacity(0.8) ?? .green.opacity(0.8)) :
                                    (roadsideItem?.color.opacity(0.8) ?? .green.opacity(0.8)),
                                lineWidth: geo.size.height * 0.01)
                        .frame(width: geo.size.width * 0.868, height: geo.size.width * 0.868)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    
                    // MARK: - Pulsing Circle
                    Circle()
                        .stroke(selectedType == 0 ?
                                (generalItem?.color.opacity(opacity) ?? .green.opacity(opacity)) :
                                    (roadsideItem?.color.opacity(opacity) ?? .green.opacity(opacity)),
                                lineWidth: geo.size.height * scale)
                        .frame(width: geo.size.width * 0.868, height: geo.size.width * 0.868)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .onAppear {
                            func pulseLoop(){
                                scale = 0.01
                                opacity = 1.0
                                withAnimation(.easeIn(duration: 0.4)) {
                                    scale = 0.05
                                    opacity = 0.0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    pulseLoop()
                                }
                            }
                            pulseLoop()
                        }
                    
                    // MARK: - Gray Inner Circle and Text
                    Circle()
                        .stroke(.gray.opacity(0.8), lineWidth: geo.size.height * 0.01)
                        .frame(width: geo.size.width * 0.824, height: geo.size.width * 0.824)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    
                    Text(selectedType == 0 ?
                         (generalItem?.health_risk_max ?? "Low"):
                            (roadsideItem?.health_risk_max ?? "Low")
                    )
                    .font(.custom("Oswald", size: geo.size.height*1/10)).fontWeight(.ultraLight)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: geo.size.height * 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .task {
                await loadAQHI()
            }
        }
        .background(Color.black.opacity(0.2).blur(radius: 10))
    }
    
    // MARK: - load AQHI
    func loadAQHI() async {
        do {
            aqhiInfo = try await fetchAQHI()
            generalItem = aqhiInfo.first { $0.type == "general" }
            roadsideItem = aqhiInfo.first { $0.type == "roadside" }
        } catch {
            print("Error:", error)
        }
    }
}

// MARK: - Total Recycling CO2 Savings View
// not used
struct totalRecyclingCO2SavingsView: View {
    var body: some View {
        GeometryReader { geo in
            VStack{
                Text("\n")
                    .font(.title).bold().foregroundColor(.white).frame(maxWidth: .infinity)
                Text("Enjoy")
                    .font(.custom("Oswald", size: geo.size.height * 1/12, relativeTo: .largeTitle))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                Text("Green Life")
                    .font(.custom("Oswald", size: geo.size.height * 1/20, relativeTo: .largeTitle))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
        }
        .background(Color.black.opacity(0.2).blur(radius: 10))
    }
}


#Preview {
    MapView()
}
