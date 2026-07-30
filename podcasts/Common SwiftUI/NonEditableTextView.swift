import SwiftUI
import UIKit

struct NonEditableTextView: UIViewRepresentable {
    let text: String
    let scrolledToBottom: Bool
    let textColor: UIColor

    init(text: String, scrolledToBottom: Bool = false, textColor: UIColor = ThemeColor.primaryText01()) {
        self.text = text
        self.scrolledToBottom = scrolledToBottom
        self.textColor = textColor
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.font = UIFont.preferredFont(forTextStyle: .body)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let textChanged = uiView.text != text
        uiView.text = text
        uiView.textColor = textColor

        if scrolledToBottom, textChanged {
            // Dispatch async to allow layout to complete before scrolling
            DispatchQueue.main.async {
                // scrollRangeToVisible forces TextKit to lay out through the end
                // of the text, which contentSize-based offsets miss because
                // off-screen glyphs are laid out lazily (landing short of bottom).
                let end = NSRange(location: (uiView.text as NSString).length, length: 0)
                uiView.scrollRangeToVisible(end)
            }
        }
    }
}
