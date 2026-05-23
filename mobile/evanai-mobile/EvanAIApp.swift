//
//  EvanAIApp.swift
//  evanai-mobile
//
//  Main app entry point
//

import SwiftUI

@main
struct EvanAIApp: App {
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var webSocketManager = EvanAIWebSocketManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Connect to server on app launch
                    conversationService.connectToServer()
                }
                .onDisappear {
                    // Disconnect when app goes to background
                    conversationService.disconnectFromServer()
                }
        }
    }
}