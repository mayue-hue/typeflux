import Markdown
import SwiftUI

struct MarkdownSwiftUIView: View {
    let markdown: String

    private var document: Markdown.Document {
        Markdown.Document(parsing: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioTheme.Spacing.textCompact) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                blockView(child)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blockView(_ markup: Markup) -> AnyView {
        if let paragraph = markup as? Paragraph {
            return AnyView(inlineChildren(paragraph)
                .font(.studioBody(StudioTheme.Typography.body, weight: .regular))
                .foregroundStyle(StudioTheme.textPrimary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading))
        } else if let heading = markup as? Heading {
            return AnyView(inlineChildren(heading)
                .font(.studioBody(headingFontSize(for: heading.level), weight: .bold))
                .foregroundStyle(StudioTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, heading.level <= 2 ? StudioTheme.Spacing.xSmall : 0))
        } else if let unorderedList = markup as? UnorderedList {
            return AnyView(listView(unorderedList.children.map(\.self), orderedStart: nil))
        } else if let orderedList = markup as? OrderedList {
            return AnyView(listView(orderedList.children.map(\.self), orderedStart: Int(orderedList.startIndex)))
        } else if let blockQuote = markup as? BlockQuote {
            return AnyView(VStack(alignment: .leading, spacing: StudioTheme.Spacing.textMicro) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    blockView(child)
                }
            }
            .padding(.leading, StudioTheme.Spacing.medium)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(StudioTheme.border)
                    .frame(width: 3)
            })
        } else if let codeBlock = markup as? CodeBlock {
            return AnyView(SwiftUI.Text(codeBlock.code)
                .font(.system(size: StudioTheme.Typography.bodySmall, design: .monospaced))
                .foregroundStyle(StudioTheme.textPrimary)
                .padding(StudioTheme.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: StudioTheme.CornerRadius.small, style: .continuous)
                        .fill(StudioTheme.surfaceMuted.opacity(0.92))
                ))
        } else if markup is ThematicBreak {
            return AnyView(Divider()
                .padding(.vertical, StudioTheme.Spacing.xSmall))
        } else {
            let fallback = plainText(in: markup).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !fallback.isEmpty {
                return AnyView(SwiftUI.Text(fallback)
                    .font(.studioBody(StudioTheme.Typography.body, weight: .regular))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading))
            }
        }

        return AnyView(EmptyView())
    }

    private func listView(_ items: [Markup], orderedStart: Int?) -> some View {
        VStack(alignment: .leading, spacing: StudioTheme.Spacing.textMicro) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: StudioTheme.Spacing.xSmall) {
                    SwiftUI.Text(listMarker(index: index, orderedStart: orderedStart))
                        .font(.studioBody(StudioTheme.Typography.body, weight: .regular))
                        .foregroundStyle(StudioTheme.textPrimary)
                        .frame(width: orderedStart == nil ? 14 : 28, alignment: .trailing)

                    listItemContent(item)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func listItemContent(_ item: Markup) -> AnyView {
        if let listItem = item as? ListItem,
           listItem.childCount == 1,
           let paragraph = listItem.child(at: 0) as? Paragraph {
            return AnyView(inlineChildren(paragraph)
                .font(.studioBody(StudioTheme.Typography.body, weight: .regular))
                .foregroundStyle(StudioTheme.textPrimary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading))
        } else {
            let text = plainText(in: item).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return AnyView(SwiftUI.Text(text)
                .font(.studioBody(StudioTheme.Typography.body, weight: .regular))
                .foregroundStyle(StudioTheme.textPrimary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading))
        }
    }

    private func listMarker(index: Int, orderedStart: Int?) -> String {
        if let orderedStart {
            return "\(orderedStart + index)."
        }

        return "•"
    }

    private func inlineChildren(_ markup: Markup) -> SwiftUI.Text {
        markup.children.reduce(SwiftUI.Text("")) { partial, child in
            partial + inlineText(child)
        }
    }

    private func inlineText(_ markup: Markup) -> SwiftUI.Text {
        if let text = markup as? Markdown.Text {
            return SwiftUI.Text(text.string)
        }

        if markup is SoftBreak {
            return SwiftUI.Text("\n")
        }

        if markup is LineBreak {
            return SwiftUI.Text("\n")
        }

        if let inlineCode = markup as? InlineCode {
            return SwiftUI.Text(inlineCode.code)
                .font(.system(size: StudioTheme.Typography.bodySmall, design: .monospaced))
        }

        if let strong = markup as? Strong {
            return inlineChildren(strong).fontWeight(.semibold)
        }

        if let emphasis = markup as? Emphasis {
            return inlineChildren(emphasis).italic()
        }

        if let strikethrough = markup as? Strikethrough {
            return inlineChildren(strikethrough).strikethrough()
        }

        if let link = markup as? Markdown.Link {
            return inlineChildren(link).underline()
        }

        return inlineChildren(markup)
    }

    private func plainText(in markup: Markup) -> String {
        if let text = markup as? Markdown.Text {
            return text.string
        }

        if markup is SoftBreak || markup is LineBreak {
            return "\n"
        }

        if let inlineCode = markup as? InlineCode {
            return inlineCode.code
        }

        if let codeBlock = markup as? CodeBlock {
            return codeBlock.code
        }

        return markup.children.map { plainText(in: $0) }.joined()
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            StudioTheme.Typography.sectionTitle
        case 2:
            StudioTheme.Typography.subsectionTitle
        default:
            StudioTheme.Typography.cardTitle
        }
    }
}
