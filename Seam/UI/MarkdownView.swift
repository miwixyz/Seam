import SwiftUI

/// Rendert Markdown mit **Blockstruktur** — Überschriften, Absätze, Listen,
/// Tabellen, Trennlinien.
///
/// Warum nicht `Text(AttributedString(markdown:))`: Das beherrscht nur
/// *Inline*-Auszeichnung (fett, kursiv, Code, Links). Blockelemente wirft es
/// weg — Überschriften verlieren ihre Größe, Absätze ihren Umbruch, Listen
/// ihren Einzug. Das Ergebnis ist eine einzige Textwand, in der „# Hilfe" und
/// der folgende Satz aneinanderkleben. Genau so sah die erste Fassung aus.
///
/// Dieser Renderer ist bewusst klein: Er kann, was in `HILFE.md`,
/// `RECHTLICHES.md` und `CHANGELOG.md` tatsächlich vorkommt. Kein vollständiger
/// CommonMark-Parser — der wäre für drei kontrollierte Dateien überdimensioniert.
struct MarkdownView: View {

    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Blockmodell

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case tableRow(cells: [String], isHeader: Bool)
        case rule
        case spacer
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                result.append(.spacer)
            } else if line.hasPrefix("#") {
                flushParagraph()
                let level = line.prefix(while: { $0 == "#" }).count
                result.append(.heading(
                    level: level,
                    text: String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                ))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("|") {
                flushParagraph()
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                // Die Trennzeile |---|---| ist Syntax, kein Inhalt.
                if cells.allSatisfy({ $0.allSatisfy { c in c == "-" || c == ":" } }) {
                    continue
                }
                let isHeader = !result.contains { if case .tableRow = $0 { return true }; return false }
                    || {
                        if case .tableRow = result.last { return false }
                        return true
                    }()
                result.append(.tableRow(cells: cells, isHeader: isHeader))
            } else if line.hasPrefix("---") || line.hasPrefix("===") {
                flushParagraph()
                result.append(.rule)
            } else if line.hasPrefix("> ") {
                paragraph.append(String(line.dropFirst(2)))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return result
    }

    // MARK: - Darstellung

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level == 1 ? 2 : 10)
                .padding(.bottom, 3)

        case .paragraph(let text):
            Text(inline(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").font(.callout).foregroundStyle(.secondary)
                Text(inline(text))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 3)

        case .tableRow(let cells, let isHeader):
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    Text(inline(cell))
                        .font(.caption)
                        .fontWeight(isHeader ? .semibold : .regular)
                        .foregroundStyle(isHeader ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)

        case .rule:
            Divider().padding(.vertical, 5)

        case .spacer:
            Spacer().frame(height: 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.bold)
        case 2: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    /// Inline-Auszeichnung darf `AttributedString` übernehmen — das kann es gut.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
