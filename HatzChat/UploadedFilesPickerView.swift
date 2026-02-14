import SwiftUI

struct UploadedFilesPickerView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading: Bool = false
    @State private var files: [RemoteFile] = []
    @State private var selectedID: RemoteFile.ID?
    @State private var searchText: String = ""
    @State private var errorText: String?

    private var selectedFile: RemoteFile? {
        guard let selectedID else { return nil }
        return files.first(where: { $0.id == selectedID })
    }

    private var filteredFiles: [RemoteFile] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return files }
        return files.filter { f in
            f.file_name.lowercased().contains(q) || f.file_uuid.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Uploaded Files")
                .font(.headline)

            Spacer()

            if isLoading {
                ProgressView().scaleEffect(0.85)
            }

            Button("Refresh") { refresh() }
                .buttonStyle(.bordered)

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var content: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by name or UUID", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding([.top, .horizontal], 12)

                List(selection: $selectedID) {
                    ForEach(filteredFiles) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.file_name)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Text(f.file_uuid)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                if let bytes = f.bytes {
                                    Text(Self.formatBytes(bytes))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let tokens = f.tokens {
                                    Text("\(tokens) tok")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(f.id as RemoteFile.ID?)
                    }
                }
            }
            .frame(minWidth: 460)

            Divider()

            detailsPanel
                .frame(minWidth: 260)
        }
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)
                .padding(.top, 12)

            if let f = selectedFile {
                Group {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(f.file_name)
                        .textSelection(.enabled)

                    Text("UUID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text(f.file_uuid)
                        .font(.caption)
                        .textSelection(.enabled)

                    if let bytes = f.bytes {
                        Text("Size")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(Self.formatBytes(bytes))
                            .font(.caption)
                    }

                    if let tokens = f.tokens {
                        Text("Tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text("\(tokens)")
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 12)

                Spacer()
            } else {
                Text("Select a file to see details.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                Spacer()
            }

            if let errorText {
                Divider()
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if store.selectedConversation == nil {
                Text("Select a chat (or create a new one) to attach a file.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New Chat") { store.newConversation() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Attach an existing upload to the selected chat. No re-upload needed.")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Forward-thinking: placeholder for future server-side delete support.
            Button("Delete from Server") {
                // Not supported by the current Hatz API.
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .help("Not supported by the Hatz API yet.")

            Button("Add to Chat") {
                addSelectedToChat()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFile == nil || store.selectedConversation == nil)
        }
        .padding(12)
    }

    private func refresh() {
        guard !store.apiKey.isEmpty else {
            errorText = "No API key set. Open Settings and enter your Hatz API key."
            return
        }

        isLoading = true
        errorText = nil

        Task {
            do {
                let client = HatzClient(apiKey: store.apiKey)
                let list = try await client.listFiles()

                await MainActor.run {
                    self.files = list
                    self.isLoading = false

                    // Keep selection if possible
                    if let sel = self.selectedID, !self.files.contains(where: { $0.id == sel }) {
                        self.selectedID = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    private func addSelectedToChat() {
        guard let f = selectedFile else { return }
        guard var convo = store.selectedConversation else { return }

        // Avoid duplicates in the same chat
        if convo.attachments.contains(where: { $0.fileUUID == f.file_uuid }) {
            dismiss()
            return
        }

        convo.attachments.append(
            Attachment(displayName: f.file_name, fileUUID: f.file_uuid)
        )
        convo.touch()
        store.updateConversation(convo, persist: true)

        dismiss()
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
}
