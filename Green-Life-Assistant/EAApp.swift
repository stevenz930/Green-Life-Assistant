//
//  EAApp.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI

@main
struct EAApp: App {
    // 初始化状态管理器
    @State private var authManager = AuthManager()
    @State private var todayCFManager = TodayCFManager()
    @State private var totalCFManager = TotalCFManager()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    // isAuthenticated：进入主界面
                    ContentView()
                        .environment(authManager)
                        .environment(todayCFManager)
                        .environment(totalCFManager)
                } else {
                    // !isAuthenticated：进入登录界面
                    AuthView()
                        .environment(authManager)
                }
            }
            .id(authManager.isAuthenticated)
            .animation(.easeInOut, value: authManager.isAuthenticated)
        }
    }
}
