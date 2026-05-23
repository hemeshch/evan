//
//  EvanAIWebSocketManager.swift
//  evanai-mobile
//
//  WebSocket manager for real-time communication with EvanAI server
//

import Foundation
import Combine

class EvanAIWebSocketManager: NSObject, ObservableObject {
    static let shared = EvanAIWebSocketManager()

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let serverURL = EvanAIConfig.webSocketURL

    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var lastError: String?

    // Message subjects for different types
    let agentResponseSubject = PassthroughSubject<AgentResponseMessage, Never>()
    let fileUploadSubject = PassthroughSubject<AgentFileUploadMessage, Never>()
    let rawMessageSubject = PassthroughSubject<String, Never>()

    private var cancellables = Set<AnyCancellable>()
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // MARK: - Initialization

    override init() {
        super.init()
        self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    }

    // MARK: - Connection Management

    func connect() {
        guard !isConnected else { return }

        disconnect() // Clean up any existing connection

        webSocketTask = urlSession.webSocketTask(with: serverURL)
        webSocketTask?.resume()

        isConnected = true
        connectionStatus = "Connected"
        reconnectAttempts = 0

        print("✓ WebSocket connected to EvanAI server")
        receiveMessage()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        isConnected = false
        connectionStatus = "Disconnected"
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionStatus = "Failed to reconnect"
            lastError = "Maximum reconnection attempts reached"
            return
        }

        reconnectAttempts += 1
        connectionStatus = "Reconnecting... (Attempt \(reconnectAttempts))"

        let delay = Double(reconnectAttempts) * 2.0 // Exponential backoff
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            self.connect()
        }
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.handleDisconnection(error: error)

            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue receiving messages
                self.receiveMessage()
            }
        }
    }

    private func handleMessage(_ text: String) {
        print("📨 Received message: \(text)")

        // Publish raw message
        rawMessageSubject.send(text)

        // Try to decode as protocol message
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(ProtocolMessage.self, from: data)

            // Handle based on message type
            switch message.type {
            case "agent_response":
                if let agentResponse = try? JSONDecoder().decode(AgentResponseMessage.self, from: data) {
                    DispatchQueue.main.async {
                        self.agentResponseSubject.send(agentResponse)
                    }
                }

            case "agent_file_upload":
                if let fileUpload = try? JSONDecoder().decode(AgentFileUploadMessage.self, from: data) {
                    DispatchQueue.main.async {
                        self.fileUploadSubject.send(fileUpload)
                    }
                }

            default:
                print("Unhandled message type: \(message.type)")
            }
        } catch {
            print("Failed to decode message: \(error)")
        }
    }

    private func handleDisconnection(error: Error) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
            self.lastError = error.localizedDescription
            self.attemptReconnect()
        }
    }

    // MARK: - Sending Messages

    func sendPrompt(conversationId: String, prompt: String) async throws {
        let message = NewPromptMessage(conversationId: conversationId, prompt: prompt)

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.encodingFailed
        }

        try await sendMessage(jsonString)
    }

    private func sendMessage(_ text: String) async throws {
        guard let webSocketTask = webSocketTask, isConnected else {
            throw NetworkError.notConnected
        }

        let message = URLSessionWebSocketTask.Message.string(text)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask.send(message) { error in
                if let error = error {
                    print("❌ Failed to send message: \(error)")
                    continuation.resume(throwing: error)
                } else {
                    print("✓ Message sent successfully")
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Broadcast API

    func broadcast(message: [String: Any]) async throws -> [String: Any] {
        let url = EvanAIConfig.broadcastURL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try JSONSerialization.data(withJSONObject: message, options: [])
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw NetworkError.decodingFailed
        }

        return json
    }

    // MARK: - Latest Data API

    func fetchLatestData() async throws -> ProtocolMessage? {
        let url = EvanAIConfig.latestURL

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }

        let message = try JSONDecoder().decode(ProtocolMessage.self, from: data)
        return message
    }
}

// MARK: - URLSessionWebSocketDelegate

extension EvanAIWebSocketManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket did open")
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionStatus = "Connected"
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket did close with code: \(closeCode)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
            self.attemptReconnect()
        }
    }
}

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case notConnected
    case encodingFailed
    case decodingFailed
    case invalidResponse
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .encodingFailed:
            return "Failed to encode message"
        case .decodingFailed:
            return "Failed to decode response"
        case .invalidResponse:
            return "Invalid server response"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}