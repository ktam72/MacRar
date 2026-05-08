import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    @Binding var logMessages: [String]

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        updateTextView(textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        updateTextView(textView)
    }

    private func updateTextView(_ textView: NSTextView) {
        let logText = logMessages.joined(separator: "\n")
        textView.string = logText

        // 最新のログまでスクロール
        if !logMessages.isEmpty {
            let range = NSRange(location: textView.string.count, length: 0)
            textView.scrollRangeToVisible(range)
        }
    }
}

struct LogTextView_Previews: PreviewProvider {
    static var previews: some View {
        LogTextView(logMessages: .constant(["[10:00:00] ログ1", "[10:00:01] ログ2", "[10:00:02] ログ3"]))
            .frame(height: 200)
            .padding()
    }
}
