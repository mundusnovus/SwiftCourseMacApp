// Draws lesson text natively from its blocks. Inline text is Markdown, which SwiftUI renders: bold, italics, `code`
// and links.
import SwiftUI

/// Inline Markdown as styled text; plain text if it cannot be parsed.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

struct BlocksView: View {
    let blocks: [Block]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .textSelection(.enabled)
    }
}

struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(markdown(text))
                .font(level <= 2 ? .title2.weight(.semibold) : .title3.weight(.semibold))
                .padding(.top, 8)
        case .paragraph(let text):
            Text(markdown(text)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .code(_, let code):
            CodeBlock(code: code)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(i + 1)." : "•").foregroundStyle(.secondary).monospacedDigit()
                        Text(markdown(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .note(let kind, let blocks):
            NoteView(kind: kind, blocks: blocks)
        case .quote(let blocks):
            HStack(spacing: 12) {
                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3)
                BlocksView(blocks: blocks).foregroundStyle(.secondary)
            }
        case .table(let head, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                TableView(head: head, rows: rows)
            }
        case .rule:
            Divider()
        }
    }
}

struct CodeBlock: View {
    let code: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(Highlighter.attributed(code))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.editorText)
                .padding(14)
        }
        .background(Color.editorBackground, in: .rect(cornerRadius: 12))
    }
}

struct NoteView: View {
    let kind: String
    let blocks: [Block]
    var tint: Color {
        switch kind {
        case "Tip": .asGold
        case "Warning": .asAlert
        default: .asSea
        }
    }
    var icon: String {
        switch kind {
        case "Tip": "lightbulb"
        case "Warning": "exclamationmark.triangle"
        case "Apple Developer Program": "apple.logo"
        default: "info.circle"
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(kind).font(.headline)
                BlocksView(blocks: blocks)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.3)))
    }
}

struct TableView: View {
    let head: [String]
    let rows: [[String]]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow { ForEach(Array(head.enumerated()), id: \.offset) { _, h in Text(markdown(h)).fontWeight(.semibold) } }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(markdown(cell)).fixedSize(horizontal: false, vertical: true) } }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}
