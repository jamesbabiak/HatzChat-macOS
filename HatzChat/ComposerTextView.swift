import SwiftUI
import AppKit

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 8)

        context.coordinator.textView = textView
        context.coordinator.onSend = onSend

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = textView
        scroll.contentView.postsBoundsChangedNotifications = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text {
            tv.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var onSend: (() -> Void)?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Enter = send, Shift+Enter = newline
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    return false // allow newline
                } else {
                    onSend?()
                    return true
                }
            }
            return false
        }
    }
}
