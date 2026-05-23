//
//  Configuration.swift
//  evanai-mobile
//
//  Edit these to point at your own evanai-server deployment.
//  See server/README.md for how to stand up the Cloudflare Workers.
//

import Foundation

enum EvanAIConfig {
    static let webSocketURL = URL(string: "wss://YOUR_DATA_TRANSMITTER.workers.dev")!
    static let broadcastURL = URL(string: "https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast")!
    static let latestURL = URL(string: "https://YOUR_DATA_TRANSMITTER.workers.dev/latest")!
    static let fileUploadURL = URL(string: "https://YOUR_FILE_UPLOAD_API.workers.dev/upload")!
}
