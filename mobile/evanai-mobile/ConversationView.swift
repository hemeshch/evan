//
//  ConversationView.swift
//  evanai-mobile
//
//  Created on 9/19/25.
//

import SwiftUI
import MarkdownUI

// MARK: - Conversation View
struct ConversationView: View {
    @State private var conversation: Conversation
    @State private var inputText = ""
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool
    @StateObject private var conversationService = ConversationService.shared
    private let persistenceManager = PersistenceManager.shared

    init(conversation: Conversation) {
        self._conversation = State(initialValue: conversation)
    }

    private var canSendMessage: Bool {
        !inputText.isEmpty &&
        !isSending &&
        !conversationService.isProcessing &&
        conversationService.connectionStatus == "Connected"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Connection status bar
            if conversationService.connectionStatus != "Connected" {
                HStack {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12))
                    Text(conversationService.connectionStatus)
                        .font(.caption)
                        .fontDesign(.rounded)
                    Spacer()
                }
                .foregroundColor(.orange)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Messages scroll view
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(conversation.messages) { message in
                            messageView(for: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                    }
                }
                .onReceive(conversationService.$activeConversation) { activeConv in
                    if let activeConv = activeConv, activeConv.id == conversation.id {
                        self.conversation = activeConv
                    }
                }
            }

            // Input area at bottom
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 12) {
                    TextField("Reply to Evan...", text: $inputText, axis: .vertical)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                        .focused($isInputFocused)

                    Button(action: sendMessage) {
                        if isSending || conversationService.isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                                .background(Color.blue)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16))
                                .bold()
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(canSendMessage ? Color.blue : Color.gray)
                                .clipShape(Circle())
                        }
                    }
                    .disabled(!canSendMessage)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(UIColor.systemBackground))
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Message Views
    @ViewBuilder
    private func messageView(for message: MessageType) -> some View {
        switch message {
        case .user(let userMessage):
            UserMessageView(message: userMessage)
        case .assistant(let assistantMessage):
            AssistantMessageView(message: assistantMessage)
        case .workGroup(let workGroup):
            WorkGroupView(workGroup: workGroup)
        case .resultDownload(let download):
            ResultDownloadView(download: download, conversationId: conversation.id)
        }
    }

    // MARK: - Actions
    private func sendMessage() {
        guard !inputText.isEmpty, !isSending else { return }

        let message = inputText
        inputText = ""
        isSending = true

        // Set this as active conversation
        conversationService.setActiveConversation(conversation)

        Task {
            await conversationService.sendMessage(text: message, in: conversation)

            // Update local conversation with the latest from service
            if let activeConv = conversationService.activeConversation {
                await MainActor.run {
                    self.conversation = activeConv
                    self.isSending = false
                }
            }
        }
    }
}

// MARK: - Individual Message Views
struct UserMessageView: View {
    let message: UserMessage

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(20)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
        }
    }
}

struct AssistantMessageView: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full markdown rendering with GitHub-style theming
            Markdown(message.content)
                .markdownTheme(.gitHub)
                .markdownTextStyle {
                    FontFamily(.system(.rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(message.timestamp, style: .time)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkGroupView: View {
    @State var workGroup: WorkGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    workGroup.isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: workGroup.isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)

                    Text(workGroup.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(workGroup.status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor(for: workGroup.status).opacity(0.15))
                        .foregroundColor(statusColor(for: workGroup.status))
                        .cornerRadius(12)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if workGroup.isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(workGroup.messages.enumerated()), id: \.element.id) { index, message in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(messageColor(for: message).opacity(0.2))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 4) {
                                switch message {
                                case .thought(let text):
                                    Text(text)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.secondary)

                                case .toolCall(let tool, let parameters, let result):
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "wrench.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.purple)
                                            Text(tool)
                                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                .foregroundColor(.purple)
                                        }

                                        Text(parameters)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .padding(6)
                                            .background(Color.black.opacity(0.05))
                                            .cornerRadius(6)

                                        if let result = result {
                                            Text(result)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(.green)
                                                .padding(6)
                                                .background(Color.green.opacity(0.08))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if index < workGroup.messages.count - 1 {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .padding(.top, 8)
            }

            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(workGroup.timestamp, style: .time)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "completed": return .green
        case "in progress": return .orange
        case "failed": return .red
        default: return .blue
        }
    }

    private func messageColor(for message: WorkGroupMessage) -> Color {
        switch message {
        case .thought: return .blue
        case .toolCall: return .purple
        }
    }
}

struct ResultDownloadView: View {
    let download: ResultDownload
    let conversationId: String
    @StateObject private var conversationService = ConversationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(download.filename)
                        .font(.system(size: 15, weight: .medium, design: .rounded))

                    HStack(spacing: 8) {
                        Text(download.fileSize)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(download.url)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Download/Progress/Share button
                Group {
                    switch download.downloadState {
                    case .notStarted:
                        Button(action: {
                            Task {
                                await conversationService.downloadFile(for: download, conversationId: conversationId)
                            }
                        }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                        }

                    case .downloading:
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                                .frame(width: 24, height: 24)

                            Circle()
                                .trim(from: 0, to: download.downloadProgress)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 24, height: 24)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.2), value: download.downloadProgress)

                            if download.downloadProgress > 0 {
                                Text("\(Int(download.downloadProgress * 100))%")
                                    .font(.system(size: 8, weight: .medium, design: .rounded))
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(width: 24, height: 24)

                    case .completed:
                        if let fileURL = conversationService.getCachedFileURL(for: download) {
                            ShareLink(item: fileURL) {
                                Image(systemName: "square.and.arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.green)
                            }
                        } else {
                            Image(systemName: "square.and.arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray.opacity(0.5))
                        }

                    case .failed:
                        Button(action: {
                            Task {
                                await conversationService.downloadFile(for: download, conversationId: conversationId)
                            }
                        }) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(download.timestamp, style: .time)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        ConversationView(conversation: Conversation(
            id: "1",
            title: "Build iOS Weather App",
            subtitle: "Creating a weather forecast application",
            createdAt: Date().addingTimeInterval(-3600),
            modifiedAt: Date(),
            messages: [
                .user(UserMessage(
                    content: "Can you help me build an iOS weather app with SwiftUI that fetches data from OpenWeather API?",
                    timestamp: Date().addingTimeInterval(-3600)
                )),

                .assistant(AssistantMessage(
                    content: "I'll help you build a comprehensive iOS weather app using SwiftUI and the OpenWeather API. Let me start by setting up the project structure and implementing the core functionality.",
                    timestamp: Date().addingTimeInterval(-3550)
                )),

                .workGroup(WorkGroup(
                    title: "Setting up project structure",
                    status: "Completed",
                    timestamp: Date().addingTimeInterval(-3500),
                    messages: [
                        .thought("Need to create the main data models for weather data"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Models/WeatherData.swift",
                            result: "✓ Created WeatherData.swift"
                        ),
                        .thought("Setting up the network layer for API calls"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Services/WeatherService.swift",
                            result: "✓ Created WeatherService.swift with async/await support"
                        ),
                        .toolCall(
                            tool: "AddPackage",
                            parameters: "url: https://github.com/SwiftyJSON/SwiftyJSON",
                            result: "✓ Added SwiftyJSON package dependency"
                        )
                    ],
                    isExpanded: false
                )),

                .assistant(AssistantMessage(
                    content: "Great! I've set up the basic project structure with data models and a service layer. Now let me implement the UI components.",
                    timestamp: Date().addingTimeInterval(-3400)
                )),

                .workGroup(WorkGroup(
                    title: "Implementing UI components",
                    status: "In Progress",
                    timestamp: Date().addingTimeInterval(-3350),
                    messages: [
                        .thought("Creating the main weather view with current conditions"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Views/CurrentWeatherView.swift",
                            result: "✓ Created CurrentWeatherView with temperature display"
                        ),
                        .thought("Need to add forecast view for 5-day predictions"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Views/ForecastListView.swift",
                            result: "✓ Created ForecastListView with ScrollView"
                        ),
                        .thought("Adding location services for current location weather"),
                        .toolCall(
                            tool: "UpdateFile",
                            parameters: "path: Info.plist\nkey: NSLocationWhenInUseUsageDescription",
                            result: "✓ Added location permission description"
                        ),
                        .toolCall(
                            tool: "RunTests",
                            parameters: "target: WeatherAppTests",
                            result: nil
                        )
                    ],
                    isExpanded: true
                )),

                .user(UserMessage(
                    content: "Can you also add a search feature to look up weather for any city?",
                    timestamp: Date().addingTimeInterval(-3200)
                )),

                .assistant(AssistantMessage(
                    content: "Absolutely! I'll add a search feature that allows users to search for weather in any city worldwide. This will include autocomplete suggestions and recent searches.",
                    timestamp: Date().addingTimeInterval(-3150)
                )),

                .workGroup(WorkGroup(
                    title: "Adding city search functionality",
                    status: "Completed",
                    timestamp: Date().addingTimeInterval(-3100),
                    messages: [
                        .thought("Implementing search bar with debouncing for API efficiency"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Views/CitySearchView.swift",
                            result: "✓ Created search view with Combine debouncing"
                        ),
                        .thought("Adding local storage for recent searches"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Services/StorageService.swift",
                            result: "✓ Created StorageService with UserDefaults"
                        ),
                        .toolCall(
                            tool: "UpdateFile",
                            parameters: "path: Views/ContentView.swift\nlines: 45-67",
                            result: "✓ Integrated search into main navigation"
                        )
                    ],
                    isExpanded: false
                )),

                .resultDownload(ResultDownload(
                    filename: "WeatherApp_Source.zip",
                    fileSize: "2.8 MB",
                    url: "https://storage.evan.ai/projects/weather-app-ios-v1.zip",
                    timestamp: Date().addingTimeInterval(-3000)
                )),

                .assistant(AssistantMessage(
                    content: "## ✨ Weather App Completed!\n\nI've successfully built your iOS weather application with the following features:\n\n### Core Features\n• **Real-time weather data** from OpenWeather API\n• **Current conditions** and 5-day forecast\n• **City search** with autocomplete suggestions\n• **Location-based weather** using device GPS\n\n### UI/UX Enhancements\n• Clean SwiftUI interface with smooth animations\n• Dark mode support\n• Persistent storage for favorite cities\n• Pull-to-refresh functionality\n\n### Next Steps\n1. Add your OpenWeather API key in `WeatherService.swift`\n2. Test the app on your device\n3. Consider adding weather alerts or widgets\n\nWould you like me to implement any additional features?",
                    timestamp: Date().addingTimeInterval(-2950)
                )),

                .user(UserMessage(
                    content: "This looks great! Can you generate some documentation for the API integration?",
                    timestamp: Date().addingTimeInterval(-2800)
                )),

                .workGroup(WorkGroup(
                    title: "Generating API documentation",
                    status: "Completed",
                    timestamp: Date().addingTimeInterval(-2750),
                    messages: [
                        .thought("Creating comprehensive API integration guide"),
                        .toolCall(
                            tool: "CreateFile",
                            parameters: "path: Documentation/API_Guide.md",
                            result: "✓ Created API integration guide with examples"
                        ),
                        .thought("Adding inline code documentation"),
                        .toolCall(
                            tool: "UpdateFiles",
                            parameters: "pattern: **/*.swift\naction: add-documentation",
                            result: "✓ Added documentation to 12 Swift files"
                        )
                    ],
                    isExpanded: false
                )),

                .resultDownload(ResultDownload(
                    filename: "API_Documentation.pdf",
                    fileSize: "456 KB",
                    url: "https://storage.evan.ai/docs/weather-api-guide.pdf",
                    timestamp: Date().addingTimeInterval(-2700)
                )),

                .assistant(AssistantMessage(
                    content: "I've generated complete documentation for the API integration, including setup instructions, endpoint descriptions, and code examples. The documentation is available in both Markdown and PDF formats.",
                    timestamp: Date().addingTimeInterval(-2650)
                ))
            ]
        ))
    }
}
