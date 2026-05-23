//
//  EvanAINetworkModels.swift
//  evanai-mobile
//
//  Network models for EvanAI protocol communication
//

import Foundation

// MARK: - Protocol Message Types

enum MessageRecipient: String, Codable {
    case agent = "agent"
    case userDevice = "user_device"
    case all = "all"
}

enum EvanAIMessageType: String, Codable {
    case newPrompt = "new_prompt"
    case agentResponse = "agent_response"
    case agentFileUpload = "agent_file_upload"
}

// MARK: - Base Protocol Message

struct ProtocolMessage: Codable {
    let recipient: String
    let type: String
    let payload: MessagePayload
    let timestamp: Int64?

    // Additional fields for broadcasts
    let device: String?
    let format: String?
}

// MARK: - Message Payloads

struct MessagePayload: Codable {
    let conversationId: String?
    let prompt: String?
    let resourceUrl: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case prompt
        case resourceUrl = "resource_url"
        case description
    }
}

// MARK: - Outgoing Messages

struct NewPromptMessage: Codable {
    let recipient: String = "agent"
    let type: String = "new_prompt"
    let payload: NewPromptPayload
    let timestamp: Int64

    init(conversationId: String, prompt: String) {
        self.payload = NewPromptPayload(conversationId: conversationId, prompt: prompt)
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

struct NewPromptPayload: Codable {
    let conversationId: String
    let prompt: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case prompt
    }
}

// MARK: - Incoming Messages

struct AgentResponseMessage: Codable {
    let device: String?
    let format: String?
    let recipient: String
    let type: String
    let payload: AgentResponsePayload
    let timestamp: Int64?
}

struct AgentResponsePayload: Codable {
    let conversationId: String
    let prompt: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case prompt
    }
}

struct AgentFileUploadMessage: Codable {
    let device: String?
    let format: String?
    let recipient: String
    let type: String
    let payload: FileUploadPayload
    let timestamp: Int64?
}

struct FileUploadPayload: Codable {
    let conversationId: String
    let resourceUrl: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case resourceUrl = "resource_url"
        case description
    }
}

// MARK: - File Upload Response

struct FileUploadResponse: Codable {
    let success: Bool
    let fileName: String
    let downloadUrl: String
    let supabaseUrl: String
    let originalName: String
    let size: Int
    let type: String
}