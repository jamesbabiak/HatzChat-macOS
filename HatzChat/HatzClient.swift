import Foundation

struct AIModel: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let developer: String
    let display_name: String
    let max_tokens: Int
    let vision: Bool
}

private struct ModelsResponse: Codable {
    let data: [AIModel]
}

private struct FilesResponse: Codable {
    let data: [RemoteFile]
}

private struct CompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
            let role: String
        }
        let message: Message
    }
    let choices: [Choice]
    let model: String
}

private struct StreamingChunk: Codable {
    let type: String
    let message: String
}

final class HatzClient {
    // Keep as-is for the rest of the app
    private let baseURL = URL(string: "https://ai.hatz.ai/v1")!
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func fetchModels() async throws -> [AIModel] {
        // Spec: GET /chat/models
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/models"))
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.requireOK(resp, data: data)

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data
    }

    /// List all files uploaded for this API key (GET /v1/files/)
    func listFiles() async throws -> [RemoteFile] {
        // IMPORTANT:
        // baseURL is https://ai.hatz.ai/v1 (no trailing slash)
        // Using a relative URL like "files/" would resolve to https://ai.hatz.ai/files/
        // So we explicitly hit the correct endpoint:
        let url = URL(string: "https://ai.hatz.ai/v1/files/")!

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.requireOK(resp, data: data)

        let decoded = try JSONDecoder().decode(FilesResponse.self, from: data)
        return decoded.data
    }

    /// Upload a file. The OpenAPI schema does not document the response fields.
    /// We upload successfully and then try to extract a UUID-like string from the response body.
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> (rawJSON: String, fileUUID: String?) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL.appendingPathComponent("files/upload"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        req.httpBody = body

        let (respData, resp) = try await URLSession.shared.data(for: req)
        try Self.requireOK(resp, data: respData)

        let raw = String(data: respData, encoding: .utf8) ?? ""
        let extracted = Self.firstUUID(in: raw)
        return (raw, extracted)
    }

    /// Send a completion request. If stream=true, `onToken` is called as chunks arrive.
    func chatComplete(
        model: String,
        messages: [[String: String]],
        fileUUIDs: [String],
        stream: Bool,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {

        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": stream,
            "auto_tool_selection": true,
            "file_uuids": fileUUIDs
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        if !stream {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            try Self.requireOK(resp, data: respData)
            let decoded = try JSONDecoder().decode(CompletionResponse.self, from: respData)
            return decoded.choices.first?.message.content ?? ""
        }

        // STREAMING:
        let (asyncBytes, resp) = try await URLSession.shared.bytes(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "HatzClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response."])
        }

        guard (200...299).contains(http.statusCode) else {
            var errData = Data()
            for try await b in asyncBytes { errData.append(b) }
            let msg = String(data: errData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "HatzClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        var buffer = ""

        for try await b in asyncBytes {
            if Task.isCancelled { break }

            if let s = String(data: Data([b]), encoding: .utf8) {
                buffer.append(s)
            }

            while let newlineIndex = buffer.firstIndex(of: "\n") {
                let rawLine = String(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)

                let line = rawLine.replacingOccurrences(of: "\r", with: "")

                let cleaned = Self.cleanStreamingLine(line)
                if cleaned.isEmpty { continue }
                if cleaned == "[DONE]" { return "" }

                if let data = cleaned.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(StreamingChunk.self, from: data) {
                    await onToken(decoded.message)
                } else {
                    await onToken(cleaned)
                }
            }
        }

        return ""
    }

    private static func requireOK(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "HatzClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response."])
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "HatzClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private static func cleanStreamingLine(_ line: String) -> String {
        if line.hasPrefix("data:") {
            return String(line.dropFirst(5))
        }
        return line
    }

    private static func firstUUID(in text: String) -> String? {
        let pattern = #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }
}
