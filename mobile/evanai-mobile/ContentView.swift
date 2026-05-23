//
//  ContentView.swift
//  evanai-mobile
//
//  Created by Michel Guo on 9/19/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @StateObject private var conversationService = ConversationService.shared
    @State private var inputText = ""
    @State private var navigateToNewConversation = false
    @State private var newConversation: Conversation?
    @State private var tapCount = 0
    @State private var tapResetTimer: Timer?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 15) {
                Text("What do you want done today?")
                    .font(.largeTitle)
                    .fontDesign(.rounded)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 70)
                    .padding(.bottom, 10)
                    .onTapGesture {
                        handleTitleTap()
                    }

                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(conversationService.connectionStatus == "Connected" ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(conversationService.connectionStatus)
                        .font(.caption)
                        .fontDesign(.rounded)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 30)

                // Unified text input box
                ZStack {
                    HStack {
                        TextField("Do Anything...", text: $inputText)
                            .font(.system(size: 16.0, weight: .medium, design: .rounded))
                            .padding(.leading, 20)
                            .padding(.trailing, 60)
                            .padding(.vertical, 15)

                        Spacer()
                    }
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(25)

                    HStack {
                        Spacer()

                        Button(action: {
                            // Send action
                            if !inputText.isEmpty {
                                createAndNavigateToConversation(with: inputText)
                            }
                        }) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18))
                                .bold()
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(inputText.isEmpty ? Color.gray.opacity(0.5) : Color.blue)
                                .clipShape(Circle())
                        }
                        .disabled(inputText.isEmpty)
                        .padding(.trailing, 5)
                    }
                }

                // Dictate button
                Button(action: {
                    // Create a new conversation for voice input
                    createAndNavigateToConversation(with: nil)
                }) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                        Text("Talk to Evan")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
            }.padding(.bottom, 90)

            // Past Tasks List
            VStack(alignment: .leading, spacing: 12) {
                Text("Past Tasks")
                    .font(.title2)
                    .fontDesign(.rounded)
                    .bold()
                    .padding(.bottom, 2)
                    .padding(.leading, 3)

                ScrollView {
                    if persistenceManager.conversationItems.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "message.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.5))

                            Text("No conversations yet")
                                .font(.headline)
                                .fontDesign(.rounded)
                                .foregroundColor(.gray)

                            Text("Start by typing or talking to Evan")
                                .font(.caption)
                                .fontDesign(.rounded)
                                .foregroundColor(.gray.opacity(0.8))
                        }
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(persistenceManager.conversationItems) { item in
                                NavigationLink(destination: ConversationView(conversation: item.conversation)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.body)
                                                .fontDesign(.rounded)
                                                .fontWeight(.medium)
                                                .foregroundStyle(Color.primary)
                                            Text(item.subtitle)
                                                .font(.caption)
                                                .fontDesign(.rounded)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer(minLength: 0)

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 15)
                                    .padding(.horizontal, 18)
                                    .background(Color.gray.opacity(0.10))
                                    .cornerRadius(15)
                                }
                            }
                        }.padding(.bottom, 100)
                    }
                }
            }
            }
            .padding()
            .ignoresSafeArea(.keyboard, edges: .all)
            .ignoresSafeArea(.all, edges: .bottom)
            .navigationBarHidden(true)
            .background(
                NavigationLink(
                    destination: newConversation.map { ConversationView(conversation: $0) },
                    isActive: $navigateToNewConversation
                ) {
                    EmptyView()
                }
            )
            .onAppear {
                // Ensure connection is established
                if conversationService.connectionStatus != "Connected" {
                    conversationService.connectToServer()
                }
            }
        }
    }

    // MARK: - Methods

    private func createAndNavigateToConversation(with prompt: String?) {
        let title = prompt ?? "New Conversation"
        let conversation = conversationService.createConversation(title: title)

        newConversation = conversation
        navigateToNewConversation = true
        inputText = ""

        // If there's a prompt, send it after navigation
        if let prompt = prompt {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // Small delay for navigation
                await conversationService.sendMessage(text: prompt, in: conversation)
            }
        }
    }

    private func handleTitleTap() {
        // Cancel previous timer
        tapResetTimer?.invalidate()

        // Increment tap count
        tapCount += 1

        // If 5 taps reached, clear data and exit
        if tapCount >= 5 {
            persistenceManager.clearAllData()
            exit(0)
        }

        // Reset tap count after 1 second of no taps
        tapResetTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            tapCount = 0
        }
    }
}

#Preview {
    ContentView()
}
