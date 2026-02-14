import SwiftUI

@main
struct HatzChatApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    store.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Chat") { store.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
