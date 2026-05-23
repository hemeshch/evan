//
//  PersistenceManager.swift
//  evanai-mobile
//
//  Created on 9/19/25.
//

import Foundation
import SwiftUI
import Combine

final class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    @Published var conversationItems: [ConversationItem] = []

    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let conversationsFile: URL

    private init() {
        self.conversationsFile = documentsDirectory.appendingPathComponent("conversations.json")
        loadConversations()
    }

    // MARK: - Public Methods

    func saveConversations() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let data = try encoder.encode(conversationItems)
            try data.write(to: conversationsFile)

            print("✓ Saved \(conversationItems.count) conversations to disk")
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    func loadConversations() {
        guard FileManager.default.fileExists(atPath: conversationsFile.path) else {
            print("No saved conversations found")
            conversationItems = []
            return
        }

        do {
            let data = try Data(contentsOf: conversationsFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            conversationItems = try decoder.decode([ConversationItem].self, from: data)
            print("✓ Loaded \(conversationItems.count) conversations from disk")
        } catch {
            print("Failed to load conversations: \(error)")
            conversationItems = []
        }
    }

    func addConversation(_ item: ConversationItem) {
        conversationItems.insert(item, at: 0)
        saveConversations()
    }

    func updateConversation(_ conversation: Conversation) {
        if let index = conversationItems.firstIndex(where: { $0.conversation.id == conversation.id }) {
            conversationItems[index].conversation = conversation
            saveConversations()
        }
    }

    func deleteConversation(at offsets: IndexSet) {
        conversationItems.remove(atOffsets: offsets)
        saveConversations()
    }

    // MARK: - Debug/Reset Methods (Not exposed in UI)

    /// Clears all persisted data - useful for testing and development
    /// Call with: PersistenceManager.shared.clearAllData()
    func clearAllData() {
        conversationItems = []

        do {
            // Clear conversation data
            if FileManager.default.fileExists(atPath: conversationsFile.path) {
                try FileManager.default.removeItem(at: conversationsFile)
                print("✓ Cleared all conversation data from disk")
            }

            // Clear all downloaded files
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let downloadedFiles = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)

            var deletedCount = 0
            for fileURL in downloadedFiles {
                // Delete files that start with "download_" (our naming pattern)
                if fileURL.lastPathComponent.hasPrefix("download_") {
                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                    print("✓ Deleted downloaded file: \(fileURL.lastPathComponent)")
                }
            }
            if deletedCount > 0 {
                print("✓ Cleared \(deletedCount) downloaded files")
            }

        } catch {
            print("Failed to clear data: \(error)")
        }
    }

    /// Exports all conversations to a shareable format
    func exportAllConversations() -> URL? {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let data = try encoder.encode(conversationItems)
            let exportFile = documentsDirectory.appendingPathComponent("conversations_export_\(Date().timeIntervalSince1970).json")
            try data.write(to: exportFile)

            return exportFile
        } catch {
            print("Failed to export conversations: \(error)")
            return nil
        }
    }

    /// Imports conversations from a JSON file
    func importConversations(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let imported = try decoder.decode([ConversationItem].self, from: data)
            conversationItems.append(contentsOf: imported)
            saveConversations()

            print("✓ Imported \(imported.count) conversations")
            return true
        } catch {
            print("Failed to import conversations: \(error)")
            return false
        }
    }

    // MARK: - Debug Info

    var debugInfo: String {
        """
        Persistence Manager Debug Info:
        - Conversations stored: \(conversationItems.count)
        - Storage location: \(conversationsFile.path)
        - File exists: \(FileManager.default.fileExists(atPath: conversationsFile.path))
        - File size: \(getFileSize() ?? "Unknown")
        """
    }

    private func getFileSize() -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: conversationsFile.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}