//
//  ContentView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(TotalCFManager.self) private var totalCFManager
    
    @State private var selectedTab: Int = 0
    
    @State private var carbonFootprint: Double = 1145.14
    @State private var showingCarbonDetails: Bool = false
    
    @State private var showingAIChat: Bool = false
    
    @State private var tabViewBottomAccessoryWidth: CGFloat = 210
    
    var body: some View {
        // MARK: - Tab
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "house.fill", value: 0) {
                DashboardView()
            }
            Tab("Map", systemImage: "globe", value: 1) {
                MapView()
            }
//            Tab("Scan", systemImage: "camera", value: 2) {
//                if selectedTab == 2 {
//                    ScanView(isSessionActive: true)
//                } else {
//                    Color.clear
//                }
//            }
            Tab("AR", systemImage: "camera", value: 2) {
                if selectedTab == 2 {
                    ARPlatformAnchorTestView(isActive: true)
                } else {
                    Color.clear
                }
            }
            Tab("News", systemImage: "newspaper", value: 3) {
                ActivityView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 4, role: .search) {
                ProfileView()
            }
        }
        .tint(Color("LushDeep"))
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory{
            TabViewBottomAccessoryButton(carbonFootprint: $carbonFootprint, tabViewBottomAccessoryWidth: $tabViewBottomAccessoryWidth, showingCarbonDetails: $showingCarbonDetails, showingAIChat: $showingAIChat)
                .background(tabViewBottomAccessoryWidth < 210 ? Color.green : Color.clear)
        }
        .sheet(isPresented: $showingCarbonDetails) {
            CFInputView()
        }
        .fullScreenCover(isPresented: $showingAIChat) {
            AIChatView()
        }
        .task {
            do {
                if let userId = authManager.currentUser?.id {
                    totalCFManager.totalCF = try await fetchTotalCF(userID: userId)
                    carbonFootprint = totalCFManager.totalCF
                    print("总碳足迹: \(carbonFootprint) kg CO₂e")
                }
            } catch {
                print("获取数据失败: \(error)")
            }
        }
    }
}

// MARK: - TabView Bottom Accessory
struct TabViewBottomAccessoryButton: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(TodayCFManager.self) private var todayCFManager
    
    @Binding var carbonFootprint: Double
    @Binding var tabViewBottomAccessoryWidth: CGFloat
    @Binding var showingCarbonDetails: Bool
    @Binding var showingAIChat: Bool
    
    
    func formatEmission(_ input: Double) -> String {
        let value = input + todayCFManager.todayCF
        if value >= 1000 {
            return String(format: "%.2f t  CO₂e", value / 1000)
        } else {
            return String(format: "%.2f kg  CO₂e", value)
        }
    }
    
    var body: some View {
        
        GeometryReader { geometry in
            HStack {
                Button(action:{
                    showingCarbonDetails = true
                    print(showingCarbonDetails)
                }) {
                    HStack(alignment: .center) {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(tabViewBottomAccessoryWidth < 210 ? Color.white : Color.green)
                        if tabViewBottomAccessoryWidth < 210 {
                            // Text("").frame(height: 30).foregroundStyle(.white)
                        } else {
                            Text("CF").frame(height: 30)
                        }
                        Text(formatEmission(carbonFootprint))
                            .foregroundStyle((tabViewBottomAccessoryWidth < 210 ? Color.white : Color.black))
                            .bold()
                    }
                }
                
                Spacer()
                Divider()
                    .frame(height: 20)
                    .background(tabViewBottomAccessoryWidth < 210 ? Color.white : Color.gray)
                Spacer()
                
                Button(action:{
                    showingAIChat = true
                    print("Chat with AI!!!")
                }) {
                    HStack(alignment: .center) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(tabViewBottomAccessoryWidth < 210 ? Color.white : Color.blue)
                        if tabViewBottomAccessoryWidth < 210 {
                            // Text("Assistant").frame(height: 30).foregroundStyle(.white)
                        } else {
                            Text("Assistant").frame(height: 30)
                        }
                    }
                }
            }
            .onChange(of: geometry.size.width) { oldWidth, newWidth in
                self.tabViewBottomAccessoryWidth = newWidth
            }
            .frame(height: 30)
        }
        .frame(height: 30)
        .foregroundStyle(.black)
        .bold()
        .lineLimit(1)
        .padding()
    }
}

// MARK: - Carbon Footprint Input View
struct CFInputView: View{
    @Environment(AuthManager.self) private var authManager
    @Environment(TodayCFManager.self) private var todayCFManager
    
    @Environment(\.dismiss) private var dismiss
    
    static let foodItems: [Emission] = [
        Emission(name: "Beef", unit: "kg", factor: 27.0),
        Emission(name: "Lamb", unit: "kg", factor: 24.0),
        Emission(name: "Pork", unit: "kg", factor: 7.0),
        Emission(name: "Chicken", unit: "kg", factor: 6.9),
        Emission(name: "Fish", unit: "kg", factor: 5.0),
        Emission(name: "Eggs", unit: "kg", factor: 4.5),
        Emission(name: "Milk", unit: "L", factor: 3.0),
        Emission(name: "Rice", unit: "kg", factor: 2.7),
        Emission(name: "Vegetables", unit: "kg", factor: 2.0),
        Emission(name: "Fruits", unit: "kg", factor: 1.1)
    ]
    
    static let transportItems: [Emission] = [
        Emission(name: "Car travel", unit: "km", factor: 0.20),
        Emission(name: "Flight travel", unit: "km", factor: 0.12),
        Emission(name: "Bus / MTR travel", unit: "km", factor: 0.05)
    ]
    
    static let energyItems: [Emission] = [
        Emission(name: "Electricity usage", unit: "kWh", factor: 0.42),
        Emission(name: "Natural gas", unit: "m³", factor: 2.1),
        Emission(name: "Waste generated", unit: "kg", factor: 1.8)
    ]
    
    func calculateTotal(_ items: [Emission]) -> Double {
        items.reduce(0) { sum, item in
            let value = Double(item.input) ?? 0
            return sum + value * item.factor
        }
    }
    
    @State private var foods = foodItems
    @State private var transport = transportItems
    @State private var energy = energyItems
    
    var totalEmission: Double {
        calculateTotal(foods) +
        calculateTotal(transport) +
        calculateTotal(energy)
    }
    
    
    var body: some View{
        NavigationStack {
            Form {
                Section("Food Emissions") {
                    ForEach($foods) { $item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            TextField(item.unit, text: $item.input)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section("Transportation") {
                    ForEach($transport) { $item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            TextField(item.unit, text: $item.input)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section("Home Energy") {
                    ForEach($energy) { $item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            TextField(item.unit, text: $item.input)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section("Total Carbon Footprint") {
                    Text("\(totalEmission, specifier: "%.2f") kg CO₂e")
                        .font(.title2)
                        .bold()
                }
            }
            .navigationTitle("Today's CF Input")
            .toolbar{
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                // MARK: - Save Button
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await uploadCarbonRecord(value: totalEmission, userID: authManager.currentUser!.id!)
                                todayCFManager.todayCF = totalEmission
                                print("Carbon record uploaded successfully")
                            } catch {
                                print("Failed to upload carbon record: \(error)")
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
