//
//  AuthManager.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import Foundation
import Observation

@Observable
class AuthManager {
    // 初始值从 UserDefaults 读取
    var isAuthenticated: Bool = UserDefaults.standard.bool(forKey: "is_logged_in")
    
    var currentUser: User? = {
        if let data = UserDefaults.standard.data(forKey: "current_user") {
            return try? JSONDecoder().decode(User.self, from: data)
        }
        return nil
    }()
    
    // MARK: - Login
    @MainActor
    func login(_ username: String, _ password: String) async throws{
        if let loginInfo: User = try? await fetchLogin(username, password){
            //print("[AuthManager Fetch] user: \(loginInfo)")
            // 触发 SwiftUI 跳转
            self.isAuthenticated = true
            self.currentUser = loginInfo
            
            // 持久化存储
            // 存储登录状态
            UserDefaults.standard.set(true, forKey: "is_logged_in")
            
            // 存储当前用户信息
            if let encoded = try? JSONEncoder().encode(loginInfo) {
                UserDefaults.standard.set(encoded, forKey: "current_user")
            }
        }
    }
    
    // MARK: - Logout
    @MainActor
    func logout() {
        self.isAuthenticated = false
        //print(isAuthenticated)
        UserDefaults.standard.set(false, forKey: "is_logged_in")
    }
    
    // MARK: - Sign Up
    @MainActor
    func signUp(_ username: String, _ password: String) async throws{
        //print("[AuthManager Input] username: \(username), password: \(password)")
        do {
            let _: User = try await insertSignUp(username, password)
        } catch {
            throw error
        }
    }
}

