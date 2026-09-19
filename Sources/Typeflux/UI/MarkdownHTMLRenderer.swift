import Foundation
import Markdown

struct MarkdownHTMLRenderer {
    func render(markdown: String) -> String {
        var renderer = HTMLVisitor()
        return renderer.visit(Document(parsing: markdown))
    }
}

private struct HTMLVisitor: MarkupVisitor {
    private var tableColumnAlignments: [Table.ColumnAlignment?] = []
    private var currentTableColumn = 0
    private var isRenderingTableHead = false

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        defaultVisit(document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(defaultVisit(paragraph))</p>"
    }

    mutating func visitTable(_ table: Table) -> String {
        let previousAlignments = tableColumnAlignments
        tableColumnAlignments = table.columnAlignments
        defer { tableColumnAlignments = previousAlignments }
        return "<table>\(defaultVisit(table))</table>"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        let previousColumn = currentTableColumn
        let previousIsRenderingTableHead = isRenderingTableHead
        currentTableColumn = 0
        isRenderingTableHead = true
        defer {
            currentTableColumn = previousColumn
            isRenderingTableHead = previousIsRenderingTableHead
        }
        return "<thead><tr>\(defaultVisit(tableHead))</tr></thead>"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        guard !tableBody.isEmpty else { return "" }
        return "<tbody>\(defaultVisit(tableBody))</tbody>"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        let previousColumn = currentTableColumn
        currentTableColumn = 0
        defer { currentTableColumn = previousColumn }
        return "<tr>\(defaultVisit(tableRow))</tr>"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else {
            return ""
        }

        let tagName = isRenderingTableHead ? "th" : "td"
        var attributes: [String] = []
        if currentTableColumn < tableColumnAlignments.count,
           let alignment = tableColumnAlignments[currentTableColumn] {
            attributes.append(" align=\"\(htmlAlignment(alignment))\"")
        }
        if tableCell.rowspan > 1 {
            attributes.append(" rowspan=\"\(tableCell.rowspan)\"")
        }
        if tableCell.colspan > 1 {
            attributes.append(" colspan=\"\(tableCell.colspan)\"")
        }

        currentTableColumn += 1
        return "<\(tagName)\(attributes.joined())>\(defaultVisit(tableCell))</\(tagName)>"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        return "<h\(level)>\(defaultVisit(heading))</h\(level)>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\(defaultVisit(blockQuote))</blockquote>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let languageClass = codeBlock.language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
        return "<pre><code\(languageClass)>\(escapeHTML(codeBlock.code))</code></pre>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(defaultVisit(emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(defaultVisit(strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(defaultVisit(strikethrough))</del>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let destination = escapeAttribute(link.destination ?? "")
        return "<a href=\"\(destination)\">\(defaultVisit(link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let source = escapeAttribute(image.source ?? "")
        let title = image.plainText.isEmpty ? "" : " alt=\"\(escapeAttribute(image.plainText))\""
        return "<img src=\"\(source)\"\(title)>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\(defaultVisit(unorderedList))</ul>"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        return "<ol\(start)>\(defaultVisit(orderedList))</ol>"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        "<li>\(renderListItem(listItem))</li>"
    }

    mutating func visitThematicBreak(_: ThematicBreak) -> String {
        "<hr />"
    }

    mutating func visitSoftBreak(_: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_: LineBreak) -> String {
        "<br />"
    }

    mutating func visitText(_ text: Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> String {
        htmlBlock.rawHTML
    }

    private mutating func renderListItem(_ listItem: ListItem) -> String {
        if listItem.childCount == 1, let paragraph = listItem.child(at: 0) as? Paragraph {
            return paragraph.children.map { visit($0) }.joined()
        }

        return listItem.children.map { visit($0) }.joined()
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeAttribute(_ string: String) -> String {
        escapeHTML(string)
    }

    private func htmlAlignment(_ alignment: Table.ColumnAlignment) -> String {
        switch alignment {
        case .left:
            "left"
        case .center:
            "center"
        case .right:
            "right"
        }
    }
}
