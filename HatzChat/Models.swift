import Foundation

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable, CaseIterable {
        case system
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
}

struct Attachment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var displayName: String
    var fileUUID: String?   // UUID4 returned by /files/upload (or selected from /files/)
}

/// Represents a file already uploaded to Hatz and visible via GET /files/
struct RemoteFile: Identifiable, Codable, Hashable {
    var id: String { file_uuid }

    let file_uuid: String
    let file_name: String
    let tokens: Int?
    let bytes: Int?
}

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "New Chat"
    var model: String = "gpt-4o"
    var messages: [ChatMessage] = []
    var attachments: [Attachment] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    mutating func touch() { updatedAt = Date() }
}
