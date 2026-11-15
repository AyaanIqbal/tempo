import SwiftUI
import AppKit
import TempoCore

/// A plain-text Markdown editor with reliable native focus, Escape, and list entry.
struct MarkdownNotesEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let onEscape: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let editor = NotesTextView(frame: .zero)
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular); editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor; editor.textContainerInset = NSSize(width: 7, height: 8)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        editor.string = text; editor.delegate = context.coordinator
        editor.onEscape = onEscape; scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator; coordinator.parent = self
        guard let editor = coordinator.editor else { return }
        editor.onEscape = onEscape
        if editor.string != text {
            let selection = editor.selectedRange(); editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        if focused {
            Task { @MainActor [weak coordinator] in
                guard let coordinator, coordinator.parent.focused, let editor = coordinator.editor, let window = editor.window else { return }
                if window.firstResponder !== editor { window.makeFirstResponder(editor) }
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNotesEditor
        weak var editor: NotesTextView?
        init(parent: MarkdownNotesEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor { parent.text = editor.string } }
        func textDidBeginEditing(_ notification: Notification) { if !parent.focused { parent.focused = true } }
        func textDidEndEditing(_ notification: Notification) { if parent.focused { parent.focused = false } }
    }
    @MainActor final class NotesTextView: NSTextView {
        var onEscape: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape?(); return }
            if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), ["b", "i"].contains(key) {
                let range = selectedRange(); let value = (string as NSString).substring(with: range)
                let marker = key == "b" ? "**" : "_"
                insertText(marker + (value.isEmpty ? "text" : value) + marker, replacementRange: range); return
            }
            super.keyDown(with: event)
        }
        override func insertNewline(_ sender: Any?) {
            let range = selectedRange(); let source = string as NSString
            let line = source.lineRange(for: NSRange(location: range.location, length: 0))
            let before = source.substring(with: NSRange(location: line.location, length: range.location - line.location))
            let continuation = MarkdownEditing.newline(after: before)
            insertText(continuation.insertion, replacementRange: NSRange(location: range.location - continuation.removeBeforeCursor, length: range.length + continuation.removeBeforeCursor))
        }
        override func cancelOperation(_ sender: Any?) { onEscape?() }
    }
}
