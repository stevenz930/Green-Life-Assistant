//
//  ProfileView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(TodayCFManager.self) private var todayCFManager
    
    @State private var isSettingPresented: Bool = false
    
    @State private var generalItem: AQHI?
    @State private var aqhiInfo: [AQHI] = []
    
    func formatEmission(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2f t  CO₂e", value / 1000)
        } else {
            return String(format: "%.2f kg  CO₂e", value)
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Welcome, \(String(describing: authManager.currentUser!.username)) !")
                    .font(.largeTitle).bold()
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView{
                //今日碳足迹
                ZStack {
                    HStack {
                        Spacer()
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Today's Carbon Footprint")
                                .font(.title)
                                .bold()
                                .foregroundColor(.white)
                            Spacer()
                            Text(formatEmission(todayCFManager.todayCF))
                                .font(.largeTitle)
                                .bold()
                                .foregroundColor(.white)
                            Spacer()
                        }
                        Spacer()
                    }.padding()
                }
                .frame(height: 200)
                .background(
                    FlowingGradientBackgroundView(colors: [Color("LushDeep"), Color("Lush"), Color("LushDeep")])
                )
                .cornerRadius(15)
                .padding(.horizontal)
                .padding(.top, 50)
                .padding(.bottom, 10)
                
                //空气质量提醒
                ZStack {
                    HStack {
                        Spacer()
                        Text("\(generalItem?.aqhi_max ?? 0.0, specifier: "%.0f")")
                            .font(.system(size: 120))
                            .foregroundColor(.white.opacity(0.5))
                            .padding()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Today's AQHI")
                                .font(.title)
                                .bold()
                                .foregroundColor(.white)
                            Spacer()
                            Text(generalItem?.health_risk_max ?? "Low")
                                .font(.largeTitle)
                                .bold()
                                .foregroundColor(.white)
                            Spacer()
                        }
                        Spacer()
                    }.padding()
                }
                .frame(height: 200)
                .background(.blue)
                .cornerRadius(15)
                .padding(.horizontal)
                .padding(.vertical, 5)
                .task {
                    await loadAQHI()
                }
            }
            
            HStack {
                Button {
                    isSettingPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.glass)
                
                Spacer()
                
                Button("Log Out"){
                    authManager.logout()
                }
                .buttonStyle(.glass)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            
        }
        .sheet(isPresented: $isSettingPresented) {
            SettingView()
                .presentationDetents([.height(240), .medium])
        }
    }
    
    // MARK: - load AQHI
    func loadAQHI() async {
        do {
            aqhiInfo = try await fetchAQHI()
            generalItem = aqhiInfo.first { $0.type == "general" }
        } catch {
            print("Error:", error)
        }
    }
}

// MARK: - Setting View
struct SettingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    @State private var changePassword: String = ""
    @State private var changePasswordIsEmpty: Bool = false
    @State private var showingAlert: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Text("Change Password")
                        .font(.headline)
                        .padding(.top)
                    Spacer()
                }
                .padding(.horizontal)
                SecureField("Password", text: $changePassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                //.padding(.vertical, 5)
                Spacer()
            }
            .navigationTitle("Setting")
            .toolbar{
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if changePassword.isEmpty {
                            changePasswordIsEmpty = true
                        } else {
                            showingAlert = true
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // MARK: - Empty password alert
                    .alert("New Password is Empty", isPresented: $changePasswordIsEmpty) {
                        Button("OK", role: .cancel) {  }
                    } message: {
                        Text("New password is empty.")
                    }
                    
                    // MARK: - Alreday changed alert
                    .alert("Password Alreday Changed!", isPresented: $showingAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("OK", role: .destructive) {
                            Task {
                                do {
                                    try await updatePassword(userID: authManager.currentUser!.id!, newPassword: changePassword)
                                } catch {
                                    print("Failed to sign up: \(error)")
                                }
                            }
                            authManager.logout()
                            dismiss()
                        }
                    } message: {
                        Text("Press ‘OK’ to change password and log in again.")
                    }
                }
            }
        }
    }
}

#Preview {
    ProfileView()
}
