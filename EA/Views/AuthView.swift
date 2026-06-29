//
//  AuthView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager
    
    @State private var username: String = ""
    @State private var password: String = ""
    
    @State private var isLoggingIn = false
    
    @State private var isSigningUp: Bool = false
    
    var body: some View {
        ZStack {
            VStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 180))
                    .foregroundColor(.white.opacity(0.75))
                
                TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                HStack {
                    Button("Sign Up") {
                        isSigningUp = true
                    }
                    .bold()
                    .buttonStyle(.glass)
                    
                    Spacer()
                    
                    Button("Login") {
                        Task {
                            do {
                                isLoggingIn = true
                                try await authManager.login(username, password)
                                isLoggingIn = false
                            } catch {
                                print("what can I say!")
                            }
                        }
                    }
                    .bold()
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                FlowingGradientBackgroundView(colors: [Color("LushDeep"), Color("Lush"), Color("LushDeep")])
            )
            .sheet(isPresented: $isSigningUp) {
                SignUpView()
                    .presentationDetents([.height(250), .medium])
            }
            
            if isLoggingIn {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading...")
                            .padding(.top)
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                }
            }
        }
    }
}


// MARK: - Sign Up View
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    @State private var signUpUsername: String = ""
    @State private var signUpPassword: String = ""
    
    var body: some View {
        NavigationStack{
            VStack {
                TextField("Username", text: $signUpUsername)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                SecureField("Password", text: $signUpPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 5)
            }
            .navigationTitle("Sign Up")
            .toolbar{
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            do {
                                try await authManager.signUp(signUpUsername, signUpPassword)
                            } catch {
                                print("Failed to sign up: \(error)")
                            }
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

#Preview {
    AuthView()
}
