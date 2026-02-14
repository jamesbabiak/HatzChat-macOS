import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ChatStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let convo = store.selectedConversation {
                ChatView(conversation: convo)
            } else {
                VStack(spacing: 10) {
                    Text("HatzChat").font(.largeTitle).bold()
                    Text("Click “New Chat” to start.")
                        .foregroundStyle(.secondary)
                    Button("New Chat") { store.newConversation() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .onAppear {
            store.load()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject var store: ChatStore

    // Inline rename state
    @State private var renamingID: UUID? = nil
    @State private var renameDraft: String = ""
    @FocusState private var renameFocused: Bool

    // Prevent commit when we're canceling (e.g., Escape)
    @State private var suppressCommitOnFocusLoss: Bool = false

    // Uploaded files picker
    @State private var showUploadedFiles: Bool = false

    var body: some View {
        List(selection: $store.selectedConversationID) {
            Section("Chats") {
                ForEach(store.conversations) { convo in
                    chatRow(convo)
                        .tag(convo.id as UUID?)
                        .contextMenu {
                            Button("Rename") {
                                beginRename(convo)
                            }
                            Divider()
                            Button("Delete") {
                                store.deleteConversation(convo.id)
                            }
                        }
                }
            }
        }
        .navigationTitle("HatzChat")
        .onChange(of: renameFocused) { focused in
            // If focus leaves the field, commit (unless we’re canceling)
            if !focused, renamingID != nil, !suppressCommitOnFocusLoss {
                commitRenameIfNeeded()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.newConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New chat")

                Button {
                    showUploadedFiles = true
                } label: {
                    Image(systemName: "tray.full")
                }
                .help("Show uploaded files")

                Button {
                    store.deleteSelectedConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.selectedConversation == nil)
                .help("Delete selected chat")

                Button {
                    store.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showUploadedFiles) {
            UploadedFilesPickerView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func chatRow(_ convo: Conversation) -> some View {
        if renamingID == convo.id {
            TextField("", text: $renameDraft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .lineLimit(1)
                .onSubmit {
                    commitRename(convo)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        renameFocused = true
                    }
                }
                .onExitCommand {
                    // ✅ ESC while editing should CANCEL and NOT COMMIT
                    suppressCommitOnFocusLoss = true
                    cancelRename()
                    DispatchQueue.main.async {
                        suppressCommitOnFocusLoss = false
                    }
                }
        } else {
            Text(convo.title)
                .lineLimit(1)
        }
    }

    private func beginRename(_ convo: Conversation) {
        renamingID = convo.id
        renameDraft = convo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if renameDraft.isEmpty { renameDraft = "New Chat" }

        // Make sure the renamed chat is selected
        store.selectedConversationID = convo.id

        DispatchQueue.main.async {
            renameFocused = true
        }
    }

    private func cancelRename() {
        renamingID = nil
        renameDraft = ""
        renameFocused = false
    }

    private func commitRenameIfNeeded() {
        guard let id = renamingID,
              let convo = store.conversations.first(where: { $0.id == id }) else {
            cancelRename()
            return
        }
        commitRename(convo)
    }

    private func commitRename(_ convo: Conversation) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't allow empty titles; just cancel
        guard !trimmed.isEmpty else {
            cancelRename()
            return
        }

        // Only update if changed
        if trimmed != convo.title {
            var updated = convo
            updated.title = trimmed
            updated.touch()
            store.updateConversation(updated, persist: true)
        }

        cancelRename()
    }
}
