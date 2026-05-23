//
//  ConversationService.swift
//  evanai-mobile
//
//  Service to manage conversations and coordinate with EvanAI server
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ConversationService: ObservableObject {
    static let shared = ConversationService()

    // MARK: - Properties

    private let webSocketManager = EvanAIWebSocketManager.shared
    private let persistenceManager = PersistenceManager.shared

    @Published var activeConversation: Conversation?
    @Published var isProcessing = false
    @Published var connectionStatus = "Disconnected"
    @Published var lastError: String?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupSubscriptions()
        connectToServer()
    }

    private func setupSubscriptions() {
        // Monitor connection status
        webSocketManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionStatus)

        // Handle agent responses
        webSocketManager.agentResponseSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                self?.handleAgentResponse(response)
            }
            .store(in: &cancellables)

        // Handle file uploads
        webSocketManager.fileUploadSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fileUpload in
                self?.handleFileUpload(fileUpload)
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection Management

    func connectToServer() {
        webSocketManager.connect()
    }

    func disconnectFromServer() {
        webSocketManager.disconnect()
    }

    // MARK: - Conversation Management

    func createConversation(title: String) -> Conversation {
        let conversation = Conversation(
            id: UUID().uuidString,
            title: title,
            subtitle: "New conversation",
            createdAt: Date(),
            modifiedAt: Date(),
            messages: []
        )

        let item = ConversationItem(
            title: title,
            subtitle: "New conversation",
            conversation: conversation
        )

        persistenceManager.addConversation(item)
        activeConversation = conversation

        return conversation
    }

    func setActiveConversation(_ conversation: Conversation) {
        activeConversation = conversation
    }

    // MARK: - Message Sending

    func sendMessage(text: String, in conversation: Conversation) async {
        guard !text.isEmpty else { return }

        isProcessing = true

        // Add user message to conversation
        let userMessage = UserMessage(
            content: text,
            timestamp: Date()
        )

        var updatedConversation = conversation
        updatedConversation.messages.append(.user(userMessage))
        updatedConversation.modifiedAt = Date()

        activeConversation = updatedConversation
        persistenceManager.updateConversation(updatedConversation)

        // Add a work group to show processing
        let workGroup = WorkGroup(
            title: "Processing your request",
            status: "In Progress",
            timestamp: Date(),
            messages: [
                .thought("Analyzing your request..."),
                .thought("Connecting to EvanAI agent...")
            ],
            isExpanded: false
        )

        updatedConversation.messages.append(.workGroup(workGroup))
        activeConversation = updatedConversation

        do {
            // Send to server via broadcast API (since WebSocket send isn't working directly)
            let message: [String: Any] = [
                "recipient": "agent",
                "type": "new_prompt",
                "payload": [
                    "conversation_id": conversation.id,
                    "prompt": text
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            let result = try await webSocketManager.broadcast(message: message)
            print("Broadcast result: \(result)")

        } catch {
            print("Failed to send message: \(error)")
            lastError = error.localizedDescription

            // Update work group to show failure
            if let lastWorkGroup = updatedConversation.messages.last,
               case .workGroup(var workGroup) = lastWorkGroup {
                workGroup.status = "Failed"
                workGroup.messages.append(.thought("Error: \(error.localizedDescription)"))
                updatedConversation.messages[updatedConversation.messages.count - 1] = .workGroup(workGroup)
                activeConversation = updatedConversation
                persistenceManager.updateConversation(updatedConversation)
            }
        }

        isProcessing = false
    }

    // MARK: - Message Handling

    private func handleAgentResponse(_ response: AgentResponseMessage) {
        let conversationId = response.payload.conversationId
        guard var conversation = findConversation(by: conversationId) else {
            print("No conversation found for response: \(conversationId)")
            return
        }

        // Update the work group to completed
        if conversation.messages.count > 0 {
            for i in stride(from: conversation.messages.count - 1, through: 0, by: -1) {
                if case .workGroup(var workGroup) = conversation.messages[i] {
                    if workGroup.status == "In Progress" {
                        workGroup.status = "Completed"
                        workGroup.messages.append(.thought("Response received from EvanAI"))
                        conversation.messages[i] = .workGroup(workGroup)
                        break
                    }
                }
            }
        }

        // Add assistant response
        let assistantMessage = AssistantMessage(
            content: response.payload.prompt,
            timestamp: Date(timeIntervalSince1970: Double(response.timestamp ?? 0) / 1000)
        )

        conversation.messages.append(.assistant(assistantMessage))
        conversation.modifiedAt = Date()

        activeConversation = conversation
        persistenceManager.updateConversation(conversation)
    }

    private func handleFileUpload(_ fileUpload: AgentFileUploadMessage) {
        let conversationId = fileUpload.payload.conversationId
        guard var conversation = findConversation(by: conversationId) else {
            print("No conversation found for file upload: \(conversationId)")
            return
        }

        // Add file download to conversation
        var download = ResultDownload(
            filename: fileUpload.payload.description,
            fileSize: "Unknown",
            url: fileUpload.payload.resourceUrl,
            timestamp: Date(timeIntervalSince1970: Double(fileUpload.timestamp ?? 0) / 1000)
        )
        download.downloadState = .notStarted

        conversation.messages.append(.resultDownload(download))
        conversation.modifiedAt = Date()

        activeConversation = conversation
        persistenceManager.updateConversation(conversation)
    }

    private func findConversation(by id: String) -> Conversation? {
        return persistenceManager.conversationItems.first { $0.conversation.id == id }?.conversation
    }

    // MARK: - File Download

    func downloadFile(for download: ResultDownload, conversationId: String) async {
        guard var conversation = findConversation(by: conversationId) else { return }

        // Find the download in the conversation
        guard let downloadIndex = conversation.messages.firstIndex(where: { message in
            if case .resultDownload(let dl) = message {
                return dl.id == download.id
            }
            return false
        }) else { return }

        // Update state to downloading
        var updatedDownload = download
        updatedDownload.downloadState = .downloading
        updatedDownload.downloadProgress = 0.1  // Show some initial progress
        conversation.messages[downloadIndex] = .resultDownload(updatedDownload)
        activeConversation = conversation
        persistenceManager.updateConversation(conversation)

        do {
            // First, download the metadata JSON
            let metadataURL = URL(string: download.url)!
            print("📥 Fetching metadata from: \(metadataURL)")
            let (metadataData, _) = try await URLSession.shared.data(from: metadataURL)

            // Parse the JSON to get the actual download URL
            struct FileMetadata: Codable {
                let fileName: String
                let downloadUrl: String
            }

            let metadata = try JSONDecoder().decode(FileMetadata.self, from: metadataData)
            print("📥 Downloading actual file from: \(metadata.downloadUrl)")

            // Create the download task for progress tracking
            let actualFileURL = URL(string: metadata.downloadUrl)!

            // Use continuation to bridge callback to async/await
            var progressObservation: NSKeyValueObservation?
            var lastLoggedProgress = 0

            let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let downloadTask = URLSession.shared.downloadTask(with: actualFileURL) { localURL, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let localURL = localURL {
                        continuation.resume(returning: localURL)
                    } else {
                        continuation.resume(throwing: NetworkError.downloadFailed("No file received"))
                    }
                }

                // Track progress using KVO
                progressObservation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
                    Task { @MainActor in
                        // Always get fresh conversation state
                        guard var conv = self.findConversation(by: conversationId),
                              let idx = conv.messages.firstIndex(where: { msg in
                                  if case .resultDownload(let dl) = msg {
                                      return dl.id == download.id
                                  }
                                  return false
                              }) else { return }

                        // Update only the download in the current message
                        if case .resultDownload(var dl) = conv.messages[idx] {
                            dl.downloadProgress = progress.fractionCompleted
                            conv.messages[idx] = .resultDownload(dl)
                            self.activeConversation = conv
                            self.persistenceManager.updateConversation(conv)
                        }

                        // Log progress at 10% intervals, avoiding duplicates
                        let percentage = Int(progress.fractionCompleted * 100)
                        if percentage >= lastLoggedProgress + 10 {
                            print("📥 Download progress: \(percentage)%")
                            lastLoggedProgress = (percentage / 10) * 10
                        }
                    }
                }

                downloadTask.resume()
            }

            // Clean up observation
            progressObservation?.invalidate()

            // Get Documents directory (not Downloads subdirectory to avoid issues)
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!

            // Create simple filename
            let fileExtension = (metadata.fileName as NSString).pathExtension
            let finalFileName = "download_\(Date().timeIntervalSince1970).\(fileExtension)"
            let destinationURL = documentsURL.appendingPathComponent(finalFileName)

            // Remove old file if exists
            try? FileManager.default.removeItem(at: destinationURL)

            // Move from temp to documents
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            print("📥 File saved to: \(destinationURL.path)")

            // Get fresh conversation state and update download state to completed
            guard var freshConversation = findConversation(by: conversationId),
                  let freshDownloadIndex = freshConversation.messages.firstIndex(where: { message in
                      if case .resultDownload(let dl) = message {
                          return dl.id == download.id
                      }
                      return false
                  }) else { return }

            if case .resultDownload(var dl) = freshConversation.messages[freshDownloadIndex] {
                dl.downloadState = .completed
                dl.localFilePath = destinationURL.path
                dl.downloadProgress = 1.0
                freshConversation.messages[freshDownloadIndex] = .resultDownload(dl)
                activeConversation = freshConversation
                persistenceManager.updateConversation(freshConversation)
            }

        } catch {
            print("Download failed: \(error)")
            // Get fresh conversation state and update state to failed
            guard var freshConversation = findConversation(by: conversationId),
                  let freshDownloadIndex = freshConversation.messages.firstIndex(where: { message in
                      if case .resultDownload(let dl) = message {
                          return dl.id == download.id
                      }
                      return false
                  }) else { return }

            if case .resultDownload(var dl) = freshConversation.messages[freshDownloadIndex] {
                dl.downloadState = .failed
                freshConversation.messages[freshDownloadIndex] = .resultDownload(dl)
                activeConversation = freshConversation
                persistenceManager.updateConversation(freshConversation)
            }
        }
    }

    func getCachedFileURL(for download: ResultDownload) -> URL? {
        guard let localPath = download.localFilePath,
              FileManager.default.fileExists(atPath: localPath) else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }

    // MARK: - File Upload

    func uploadFile(at url: URL) async throws -> FileUploadResponse {
        let uploadURL = EvanAIConfig.fileUploadURL

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: url)
        let fileName = url.lastPathComponent

        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.uploadFailed("Invalid response")
        }

        let uploadResponse = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        return uploadResponse
    }
}