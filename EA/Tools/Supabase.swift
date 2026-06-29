//
//  Supabase.swift
//  EA
//
//  Created by Steven Z on 2026/04/17.
//

import Foundation
import Supabase

// MARK: - Supabase Client
let supabase = SupabaseClient(
  supabaseURL: URL(string: Config.supabaseURL)!,
  supabaseKey: Config.supabaseAnonKey,
  options: SupabaseClientOptions(
      auth: .init(
          emitLocalSessionAsInitialSession: true
      )
  )
)

// MARK: - Fetch AQHI Data
func fetchAQHI() async throws -> [AQHI] {
    try await supabase
        .from("aqhi")
        .select()
        .order("id", ascending: false)
        .limit(2)
        .execute()
        .value
}

// MARK: - Login
func fetchLogin(_ username: String, _ password: String) async throws -> User {
    print("[Supabase Input] username: \(username), password: \(password)")
    let users: [User] = try await supabase
        .from("user")
        .select()
        .eq("username", value: username)
        .eq("password", value: password)
        .limit(1)
        .execute()
        .value
    
    print("[Supabase Fetch] users: \(users)")
    
    return users.first!
}

// MARK: - Upload Carbon Footprint Record
// 每人每日记录唯一
func uploadCarbonRecord(value: Double, userID: Int) async throws {
    // 获取当天的日期
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let todayString = formatter.string(from: Date())
    
    let record: [String: AnyJSON] = [
        "user_id": .integer(userID),
        "today_cf": .double(value),
        "updated_at": .string(todayString)
    ]
    
    try await supabase
        .from("today_cf")
        .upsert(
            record,
            onConflict: "user_id,updated_at"
        )
        .execute()
}

// MARK: - Fetch Total Carbon Footprint
func fetchTotalCF(userID: Int) async throws -> Double {
    //print("fetchTotalCF!!!!")
    let records: [User] = try await supabase
        .from("user")
        .select()
        .eq("id", value: userID)
        .limit(1)
        .execute()
        .value
    
    //print("fetchTotalCF: \(records.first?.total_cf)")
    return records.first?.total_cf ?? 0.0
}

// MARK: - Fetch Latest Today's Carbon Footprint
func fetchLatestTodayCF(userID: Int) async throws -> Double {
    let records: [CFRecord] = try await supabase
        .from("today_cf")
        .select()
        .eq("user_id", value: userID)
        .order("updated_at", ascending: false) // 时间倒序
        .limit(1)
        .execute()
        .value
    
    print(records)
    return records.first?.today_cf ?? 0.0
}

// MARK: - Sign Up
func insertSignUp(_ username: String, _ password: String) async throws -> User {
    print("[Supabase Input] 准备注册 username: \(username)")

    // 检查用户名是否已存在
    let existingUsers: [User] = try await supabase
        .from("user")
        .select()
        .eq("username", value: username)
        .execute()
        .value

    if !existingUsers.isEmpty {
        throw NSError(domain: "SignUpError", code: 409, userInfo: [NSLocalizedDescriptionKey: "username used"])
    }

    let newUser = User(
        id: nil,
        username: username,
        password: password,
        total_cf: 0.0
    )

    // 插入数据库
    // .single() 会直接返回插入成功的那个 User 对象
    let createdUser: User = try await supabase
        .from("user")
        .insert(newUser)
        .select() // 必须加 select() 才能获取返回的插入结果
        .single()
        .execute()
        .value

    print("[Supabase Fetch] 注册成功: \(createdUser)")
    return createdUser
}

// MARK: - Update Password
func updatePassword(userID: Int, newPassword: String) async throws {
    print("[Supabase] 正在为用户 ID \(userID) 修改密码")
    
    try await supabase
        .from("user")
        .update(["password": newPassword]) // 构造更新字典
        .eq("id", value: userID)           // 匹配用户 ID
        .execute()
    
    print("[Supabase] 密码修改成功")
}
