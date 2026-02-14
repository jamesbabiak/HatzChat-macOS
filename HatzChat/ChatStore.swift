import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: UUID?
    @Published var showSettings: Bool = false

    @Published var apiKey: String = Keychain.loadAPIKey() ?? ""
    @Published var availableModels: [AIModel] = []
    @Published var isLoadingModels: Bool = false
    @Published var lastError: String?

    // Remember last-used model for new chats
    @Published var lastUsedModel: String = UserDefaults.standard.string(forKey: "hatz_last_model") ?? "gpt-4o" {
        didSet {
            UserDefaults.standard.set(lastUsedModel, forKey: "hatz_last_model")
        }
    }

    private let persistence = ChatPersistence()

    var selectedConversation: Conversation? {
        get { conversations.first(where: { $0.id == selectedConversationID }) }
        set {
            guard let newValue else { return }
            if let idx = conversations.firstIndex(where: { $0.id == newValue.id }) {
                conversations[idx] = newValue
            }
        }
    }

    func load() {
        conversations = persistence.load()

        // If we have chats but none selected yet, select first
        if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }

        // If we loaded a selected conversation, update lastUsedModel from it
        if let c = selectedConversation, !c.model.isEmpty {
            lastUsedModel = c.model
        }

        if !apiKey.isEmpty {
            Task { await refreshModels() }
        }
    }

    func save() {
        persistence.save(conversations)
    }

    func newConversation() {
        var convo = Conversation()
        convo.title = "New Chat"
        convo.model = lastUsedModel  // use last selected model by default
        conversations.insert(convo, at: 0)
        selectedConversationID = convo.id
        save()
    }

    func deleteSelectedConversation() {
        guard let id = selectedConversationID else { return }
        deleteConversation(id)
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id {
            selectedConversationID = conversations.first?.id
        }
        save()
    }

    /// Update a conversation in memory; optionally persist.
    func updateConversation(_ convo: Conversation, persist: Bool = true) {
        guard let idx = conversations.firstIndex(where: { $0.id == convo.id }) else { return }
        conversations[idx] = convo

        // Keep lastUsedModel in sync with whatever the user sets
        if !convo.model.isEmpty {
            lastUsedModel = convo.model
        }

        if persist { save() }
    }

    func setAPIKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            Keychain.deleteAPIKey()
        } else {
            try? Keychain.saveAPIKey(apiKey)
        }
        Task { await refreshModels() }
    }

    func refreshModels() async {
        guard !apiKey.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            availableModels = try await HatzClient(apiKey: apiKey).fetchModels()

            // If lastUsedModel isn’t in the list (rare), fall back to first model
            if !availableModels.isEmpty,
               !availableModels.contains(where: { $0.name == lastUsedModel }) {
                lastUsedModel = availableModels.first!.name

                // Also update currently selected conversation model if needed
                if var c = selectedConversation {
                    c.model = lastUsedModel
                    updateConversation(c)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct ChatPersistence {
    private let fileName = "chats.json"

    private func fileURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let dir = appSupport.appendingPathComponent("HatzChat", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    func load() -> [Conversation] {
        do {
            let url = try fileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.withDates.decode([Conversation].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ conversations: [Conversation]) {
        do {
            let url = try fileURL()
            let data = try JSONEncoder.withDates.encode(conversations)
            try data.write(to: url, options: [.atomic])
        } catch {
            // keep silent for simplicity
        }
    }
}

extension JSONDecoder {
    static var withDates: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var withDates: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
