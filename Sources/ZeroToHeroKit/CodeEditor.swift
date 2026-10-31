// A Swift code editor: a native text view with syntax colouring, four-space tabs and automatic indentation, and line
// numbers on the Mac. Lines with compiler errors are marked.
import SwiftUI

#if os(macOS)
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var errorLines: Set<Int> = []
    var fontSize: CGFloat = 14

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        let editor = SwiftTextView(frame: view.frame, textContainer: view.textContainer)
        editor.autoresizingMask = view.autoresizingMask
        scroll.documentView = editor
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.smartInsertDeleteEnabled = false
        editor.drawsBackground = true
        editor.backgroundColor = NSColor(Color.editorBackground)
        editor.insertionPointColor = NSColor(Color.asGold)
        editor.textContainerInset = NSSize(width: 8, height: 12)
        editor.setAccessibilityLabel("Your Swift code")
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Color.editorBackground)
        let ruler = LineNumberRuler(textView: editor)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        editor.string = text
        context.coordinator.colour(editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            editor.string = text
            context.coordinator.colour(editor)
        } else if context.coordinator.fontSize != fontSize {
            context.coordinator.colour(editor)
        }
        if let ruler = scroll.verticalRulerView as? LineNumberRuler, ruler.errorLines != errorLines {
            ruler.errorLines = errorLines
            ruler.needsDisplay = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var fontSize: CGFloat = 0
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let editor = note.object as? NSTextView else { return }
            parent.text = editor.string
            colour(editor)
            editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func colour(_ editor: NSTextView) {
            fontSize = parent.fontSize
            let font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let bold = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold)
            guard let storage = editor.textStorage else { return }
            let source = storage.string
            storage.beginEditing()
            let all = NSRange(location: 0, length: storage.length)
            storage.setAttributes([.font: font, .foregroundColor: NSColor(Color.editorText)], range: all)
            for (range, token) in Highlighter.tokens(source) {
                let r = NSRange(range, in: source)
                if let c = Highlighter.color(token) { storage.addAttribute(.foregroundColor, value: NSColor(c), range: r) }
                if token == .keyword { storage.addAttribute(.font, value: bold, range: r) }
            }
            storage.endEditing()
            editor.typingAttributes = [.font: font, .foregroundColor: NSColor(Color.editorText)]
        }
    }
}

/// Four-space tabs, and new lines keep the indentation (one level more after an opening bracket).
final class SwiftTextView: NSTextView {
    override func insertTab(_ sender: Any?) { insertText("    ", replacementRange: selectedRange()) }

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString, caret = selectedRange().location
        let lineStart = text.lineRange(for: NSRange(location: max(0, caret - 1) < text.length ? caret : max(0, caret - 1), length: 0)).location
        let before = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        var indent = String(before.prefix { $0 == " " || $0 == "\t" })
        if let last = before.trimmingCharacters(in: .whitespaces).last, "{([".contains(last) { indent += "    " }
        insertText("\n" + indent, replacementRange: selectedRange())
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // typing "}" on a line of only spaces removes one level of indentation
        if let s = string as? String, s == "}" {
            let text = self.string as NSString, caret = selectedRange().location
            let lineStart = text.lineRange(for: NSRange(location: caret, length: 0)).location
            let before = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            if before.count >= 4, before.allSatisfy({ $0 == " " }) {
                super.insertText(String(before.dropLast(4)) + "}", replacementRange: NSRange(location: lineStart, length: caret - lineStart))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }
}

/// Line numbers beside the editor; lines with errors are drawn in red.
final class LineNumberRuler: NSRulerView {
    var errorLines: Set<Int> = []
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
    }
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(Color.editorBackground).setFill()
        rect.fill()
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = text.substring(to: chars.location).components(separatedBy: "\n").count
        var index = chars.location
        let font = NSFont.monospacedDigitSystemFont(ofSize: (textView.font?.pointSize ?? 14) * 0.85, weight: .regular)
        let inset = textView.textContainerInset.height
        func draw(_ n: Int, at y: CGFloat) {
            let colour = errorLines.contains(n) ? NSColor(Color.asAlert) : NSColor.secondaryLabelColor.withAlphaComponent(0.6)
            let label = "\(n)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y - visible.minY + inset + 1), withAttributes: attrs)
        }
        while index < NSMaxRange(chars) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: lineRange.location)
            draw(line, at: layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY)
            index = NSMaxRange(lineRange)
            line += 1
        }
        if text.length == 0 || text.hasSuffix("\n") {   // the empty last line
            let y = text.length == 0 ? 0 : layout.extraLineFragmentRect.minY
            draw(line, at: y)
        }
    }
}

#else
import UIKit

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    var errorLines: Set<Int> = []
    var fontSize: CGFloat = 14

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = UIColor(Color.editorBackground)
        view.tintColor = UIColor(Color.asGold)
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.spellCheckingType = .no
        view.keyboardType = .asciiCapable
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.accessibilityLabel = "Your Swift code"
        view.text = text
        context.coordinator.colour(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text; context.coordinator.colour(view) }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            colour(view)
        }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
            guard string == "\n" else { return true }
            let text = view.text as NSString
            let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
            let before = text.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            var indent = String(before.prefix { $0 == " " })
            if let last = before.trimmingCharacters(in: .whitespaces).last, "{([".contains(last) { indent += "    " }
            view.replace(view.textRange(from: view.position(from: view.beginningOfDocument, offset: range.location)!, to: view.position(from: view.beginningOfDocument, offset: NSMaxRange(range))!)!, withText: "\n" + indent)
            return false
        }

        func colour(_ view: UITextView) {
            let font = UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let bold = UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold)
            let selected = view.selectedRange
            let source = view.text ?? ""
            let styled = NSMutableAttributedString(string: source, attributes: [.font: font, .foregroundColor: UIColor(Color.editorText)])
            for (range, token) in Highlighter.tokens(source) {
                let r = NSRange(range, in: source)
                if let c = Highlighter.color(token) { styled.addAttribute(.foregroundColor, value: UIColor(c), range: r) }
                if token == .keyword { styled.addAttribute(.font, value: bold, range: r) }
            }
            view.attributedText = styled
            view.selectedRange = selected
            view.typingAttributes = [.font: font, .foregroundColor: UIColor(Color.editorText)]
        }
    }
}
#endif
