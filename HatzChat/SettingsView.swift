import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) var dismiss

    @State private var apiKeyDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title2).bold()

            GroupBox("Hatz API Key") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Paste your Hatz API key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save") {
                            store.setAPIKey(apiKeyDraft)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear") {
                            apiKeyDraft = ""
                            store.setAPIKey("")
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("The app stores your key in macOS Keychain (local to this Mac).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox("Models") {
                VStack(alignment: .leading, spacing: 8) {
                    if store.apiKey.isEmpty {
                        Text("Set an API key to load available models.")
                            .foregroundStyle(.secondary)
                    } else if store.isLoadingModels {
                        HStack { ProgressView(); Text("Loading…") }
                    } else if store.availableModels.isEmpty {
                        Text("No models loaded yet.")
                            .foregroundStyle(.secondary)
                        Button("Reload Models") { Task { await store.refreshModels() } }
                            .buttonStyle(.bordered)
                    } else {
                        Text("Loaded \(store.availableModels.count) models.")
                            .foregroundStyle(.secondary)
                        Button("Reload Models") { Task { await store.refreshModels() } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(6)
            }

            if let err = store.lastError, !err.isEmpty {
                GroupBox("Last Error") {
                    Text(err)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 520, height: 420)
        .onAppear {
            apiKeyDraft = store.apiKey
        }
    }
}
