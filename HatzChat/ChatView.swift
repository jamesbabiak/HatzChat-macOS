import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ChatView: View {
    @EnvironmentObject var store: ChatStore

    @State private var input: String = ""
    @State private var isSending: Bool = false
    @State private var streamingTask: Task<Void, Never>?

    @State private var showUploadError: Bool = false
    @State private var uploadErrorText: String = ""

    // Streaming throttling
    @State private var pendingAppend: String = ""
    @State private var flushTask: Task<Void, Never>?

    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            Divider()
            composer
        }
        .navigationTitle(conversation.title)
        .alert("Upload failed", isPresented: $showUploadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadErrorText)
        }
        .onDisappear {
            streamingTask?.cancel()
            flushTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Model", selection: Binding(
                get: { store.selectedConversation?.model ?? store.lastUsedModel },
                set: { newModel in
                    guard var c = store.selectedConversation else { return }
                    c.model = newModel
                    store.lastUsedModel = newModel
                    store.updateConversation(c)
                }
            )) {
                if store.availableModels.isEmpty {
                    Text("gpt-4o").tag("gpt-4o")
                } else {
                    ForEach(store.availableModels) { m in
                        Text(m.display_name).tag(m.name)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 260)

            Spacer()

            if isSending {
                ProgressView().scaleEffect(0.8)
                Button("Stop") { streamingTask?.cancel() }
                    .buttonStyle(.bordered)
            }

            Button("Settings") { store.showSettings = true }
                .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.selectedConversation?.messages ?? []) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }

                    if let attachments = store.selectedConversation?.attachments, !attachments.isEmpty {
                        AttachmentsRow(attachments: attachments)
                    }
                }
                .padding(16)
            }
            .onChange(of: store.selectedConversation?.messages.count ?? 0) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: pendingAppend) { _, _ in
                // Auto-scroll while streaming
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = store.selectedConversation?.messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    pickAndUploadFile()
                } label: {
                    Image(systemName: "paperclip")
                }
                .help("Attach a file (uploads to Hatz, stores file UUID locally)")

                ComposerTextView(text: $input) {
                    send()
                }
                .frame(minHeight: 44, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1)
                )

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("Enter = send • Shift+Enter = new line • Attachments are sent via Hatz file UUIDs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func send() {
        guard !isSending else { return }
        guard !store.apiKey.isEmpty else {
            store.showSettings = true
            return
        }

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""

        isSending = true
        pendingAppend = ""

        streamingTask = Task {
            defer {
                Task { @MainActor in
                    flushTask?.cancel()
                    isSending = false
                }
            }

            guard var convo = store.selectedConversation else { return }

            // Ensure lastUsedModel stays synced with the current convo model
            if !convo.model.isEmpty {
                store.lastUsedModel = convo.model
            }

            // Add user message
            convo.messages.append(ChatMessage(role: .user, content: text))
            convo.touch()

            // Set title if it's a new chat
            if convo.title == "New Chat" {
                convo.title = String(text.prefix(48))
            }

            // Create assistant placeholder (for streaming)
            let assistantID = UUID()
            convo.messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))

            // Persist user message immediately (but not streaming deltas)
            store.updateConversation(convo, persist: true)

            let client = HatzClient(apiKey: store.apiKey)
            let fileUUIDs = convo.attachments.compactMap { $0.fileUUID }

            // Build request messages (exclude placeholder)
            var requestMessages: [[String: String]] = []

            // Strong formatting instruction (model-agnostic)
            requestMessages.append([
                "role": "system",
                "content": """
You are a helpful assistant.
Format ALL responses as clean Markdown:
- Use headings and bullet lists.
- Include blank lines between sections.
- Use tables when helpful.
Do not include debug/tool logs in the response.
"""
            ])

            requestMessages += convo.messages
                .filter { $0.id != assistantID }
                .map { ["role": $0.role.rawValue, "content": $0.content] }

            // Throttled UI update loop (prevents UI freeze)
            flushTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
                    await MainActor.run {
                        flushPending(to: assistantID)
                    }
                }
            }

            do {
                _ = try await client.chatComplete(
                    model: convo.model,
                    messages: requestMessages,
                    fileUUIDs: fileUUIDs,
                    stream: true,
                    onToken: { token in
                        let cleaned = DebugFilter.cleanStreaming(token)
                        if cleaned.isEmpty { return }
                        pendingAppend += cleaned
                    }
                )

                // Final flush
                await MainActor.run {
                    flushPending(to: assistantID, force: true)
                }

                // Final cleanup + persist once
                await MainActor.run {
                    guard var c = store.selectedConversation else { return }
                    if let idx = c.messages.firstIndex(where: { $0.id == assistantID }) {
                        c.messages[idx].content = DebugFilter.cleanFinal(c.messages[idx].content)
                        c.touch()
                        store.updateConversation(c, persist: true)
                    }
                }

            } catch {
                await MainActor.run {
                    store.lastError = error.localizedDescription
                    guard var c = store.selectedConversation else { return }
                    if let idx = c.messages.firstIndex(where: { $0.id == assistantID }) {
                        c.messages[idx].content = "Error: \(error.localizedDescription)"
                        c.touch()
                        store.updateConversation(c, persist: true)
                    }
                }
            }
        }
    }

    @MainActor
    private func flushPending(to assistantID: UUID, force: Bool = false) {
        guard !pendingAppend.isEmpty || force else { return }
        guard var c = store.selectedConversation else { return }
        guard let idx = c.messages.firstIndex(where: { $0.id == assistantID }) else { return }

        if !pendingAppend.isEmpty {
            c.messages[idx].content += pendingAppend
            pendingAppend = ""
            c.touch()
            // IMPORTANT: do NOT persist while streaming (prevents freezes)
            store.updateConversation(c, persist: false)
        }
    }

    // MARK: - File upload (keeps prior functionality)

    private func pickAndUploadFile() {
        guard !store.apiKey.isEmpty else {
            store.showSettings = true
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .data, .pdf, .plainText, .image, .rtf, .spreadsheet, .presentation, .archive
        ]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await uploadFile(url: url) }
        }
    }

    private func uploadFile(url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let mime = mimeType(for: url) ?? "application/octet-stream"
            let client = HatzClient(apiKey: store.apiKey)

            let result = try await client.uploadFile(data: data,
                                                     filename: url.lastPathComponent,
                                                     mimeType: mime)

            await MainActor.run {
                guard var convo = store.selectedConversation else { return }
                let att = Attachment(displayName: url.lastPathComponent, fileUUID: result.fileUUID)
                convo.attachments.append(att)
                convo.touch()
                store.updateConversation(convo, persist: true)
            }

            if result.fileUUID == nil {
                await MainActor.run {
                    showUploadError = true
                    uploadErrorText = "Upload succeeded but I couldn't find a file UUID in the response.\n\nRaw response:\n\(result.rawJSON)"
                }
            }
        } catch {
            await MainActor.run {
                showUploadError = true
                uploadErrorText = error.localizedDescription
            }
        }
    }

    private func mimeType(for url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType
        }
        return nil
    }
}

/// Filters out common “tool/debug” wrappers seen in model output.
private enum DebugFilter {
    static func cleanStreaming(_ token: String) -> String {
        // Drop tool wrappers early if they appear
        if token.contains("<details") || token.contains("</details>") { return "" }
        if token.contains("\"exit_code\"") && token.contains("\"output\"") { return "" }
        return token
    }

    static func cleanFinal(_ text: String) -> String {
        var t = text

        // Remove <details>…</details> blocks
        t = t.replacingOccurrences(of: #"(?s)<details.*?>.*?</details>"#,
                                  with: "",
                                  options: .regularExpression)

        // Remove common “Tool result …” remnants
        t = t.replacingOccurrences(of: #"(?im)^.*Tool result.*$"#,
                                  with: "",
                                  options: .regularExpression)

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AttachmentsRow: View {
    @EnvironmentObject var store: ChatStore
    let attachments: [Attachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments").font(.headline)
            ForEach(attachments) { a in
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                    Text(a.displayName)
                    Spacer()
                    if let uuid = a.fileUUID {
                        Text(uuid).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("(no UUID found)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        remove(a.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 6)
    }

    private func remove(_ id: UUID) {
        guard var c = store.selectedConversation else { return }
        c.attachments.removeAll { $0.id == id }
        c.touch()
        store.updateConversation(c, persist: true)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MarkdownText(text: message.content.isEmpty ? "…" : message.content)
                    .font(.body)
            }
            Spacer()
        }
        .padding(12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var label: String {
        switch message.role {
        case .system: return "System"
        case .user: return "You"
        case .assistant: return "Hatz"
        }
    }

    private var background: Color {
        switch message.role {
        case .system: return .gray.opacity(0.15)
        case .user: return .blue.opacity(0.12)
        case .assistant: return .green.opacity(0.10)
        }
    }
}
