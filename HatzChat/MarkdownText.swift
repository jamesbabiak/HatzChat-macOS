import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        // A vertical scroll is handled by the outer chat ScrollView.
        // This adds horizontal scrolling *only when needed* (e.g., long URLs, hashes, base64, code lines).
        ScrollView(.horizontal) {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Helps the system find break opportunities; still won’t break very long single “words”
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
        }
        .scrollIndicators(.visible) // shows horizontal scrollbar on macOS
    }
}
