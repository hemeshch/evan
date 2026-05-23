//
//  Models.swift
//  evanai-mobile
//
//  Created on 9/19/25.
//

import Foundation

// MARK: - ConversationItem

struct ConversationItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let subtitle: String
    var conversation: Conversation

    init(id: UUID = UUID(), title: String, subtitle: String, conversation: Conversation) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.conversation = conversation
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let createdAt: Date
    var modifiedAt: Date
    var messages: [MessageType]
}

// MARK: - Message Types

struct UserMessage: Identifiable, Codable {
    let id = UUID()
    let content: String
    let timestamp: Date
}

struct AssistantMessage: Identifiable, Codable {
    let id = UUID()
    let content: String
    let timestamp: Date
}

struct WorkGroup: Identifiable, Codable {
    let id = UUID()
    let title: String
    var status: String
    let timestamp: Date
    var messages: [WorkGroupMessage]
    var isExpanded: Bool = false
}

enum DownloadState: String, Codable {
    case notStarted
    case downloading
    case completed
    case failed
}

struct ResultDownload: Identifiable, Codable {
    let id = UUID()
    let filename: String
    let fileSize: String
    let url: String
    let timestamp: Date
    var downloadState: DownloadState = .notStarted
    var localFilePath: String?
    var downloadProgress: Double = 0.0
}

// MARK: - WorkGroup Message Types

enum WorkGroupMessage: Identifiable, Codable {
    case thought(String)
    case toolCall(tool: String, parameters: String, result: String?)

    var id: String {
        switch self {
        case .thought(let text): return text
        case .toolCall(let tool, let params, _): return "\(tool)-\(params)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case thought
        case toolCall
        case toolCallTool = "tool"
        case toolCallParameters = "parameters"
        case toolCallResult = "result"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let thought = try container.decodeIfPresent(String.self, forKey: .thought) {
            self = .thought(thought)
        } else if container.contains(.toolCall) {
            let tool = try container.decode(String.self, forKey: .toolCallTool)
            let parameters = try container.decode(String.self, forKey: .toolCallParameters)
            let result = try container.decodeIfPresent(String.self, forKey: .toolCallResult)
            self = .toolCall(tool: tool, parameters: parameters, result: result)
        } else {
            throw DecodingError.dataCorruptedError(forKey: CodingKeys.thought, in: container, debugDescription: "Unable to decode WorkGroupMessage")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .thought(let text):
            try container.encode(text, forKey: .thought)
        case .toolCall(let tool, let parameters, let result):
            try container.encode(true, forKey: .toolCall)
            try container.encode(tool, forKey: .toolCallTool)
            try container.encode(parameters, forKey: .toolCallParameters)
            try container.encodeIfPresent(result, forKey: .toolCallResult)
        }
    }
}

// MARK: - Message Type Wrapper

enum MessageType: Identifiable, Codable {
    case user(UserMessage)
    case assistant(AssistantMessage)
    case workGroup(WorkGroup)
    case resultDownload(ResultDownload)

    var id: String {
        switch self {
        case .user(let msg): return msg.id.uuidString
        case .assistant(let msg): return msg.id.uuidString
        case .workGroup(let msg): return msg.id.uuidString
        case .resultDownload(let msg): return msg.id.uuidString
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case user, assistant, workGroup, resultDownload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "user":
            let message = try container.decode(UserMessage.self, forKey: .user)
            self = .user(message)
        case "assistant":
            let message = try container.decode(AssistantMessage.self, forKey: .assistant)
            self = .assistant(message)
        case "workGroup":
            let group = try container.decode(WorkGroup.self, forKey: .workGroup)
            self = .workGroup(group)
        case "resultDownload":
            let download = try container.decode(ResultDownload.self, forKey: .resultDownload)
            self = .resultDownload(download)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .user(let message):
            try container.encode("user", forKey: .type)
            try container.encode(message, forKey: .user)
        case .assistant(let message):
            try container.encode("assistant", forKey: .type)
            try container.encode(message, forKey: .assistant)
        case .workGroup(let group):
            try container.encode("workGroup", forKey: .type)
            try container.encode(group, forKey: .workGroup)
        case .resultDownload(let download):
            try container.encode("resultDownload", forKey: .type)
            try container.encode(download, forKey: .resultDownload)
        }
    }
}