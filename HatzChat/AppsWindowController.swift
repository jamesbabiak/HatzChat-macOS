import SwiftUI
import AppKit

@MainActor
final class AppsWindowController {
    static let shared = AppsWindowController()

    private var window: NSWindow?

    func show(store: ChatStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = AppsView()
            .environmentObject(store)

        let hosting = NSHostingController(rootView: rootView)

        let w = NSWindow(contentViewController: hosting)
        w.title = "Apps"
        w.setContentSize(NSSize(width: 1100, height: 750))
        w.minSize = NSSize(width: 900, height: 600)

        w.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable
        ]

        w.isReleasedWhenClosed = false
        w.center()

        // When the window closes, release our reference so it can be recreated next time.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            // Ensure we mutate MainActor-isolated state on the main actor.
            Task { @MainActor in
                self?.window = nil
            }
        }

        self.window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

