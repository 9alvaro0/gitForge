import SwiftUI

/// `.gf-markdown` — pragmatic block-level markdown renderer for PR/MR
/// descriptions. Handles headings (`#`–`###`), unordered (`-`/`*`) and
/// ordered (`1.`) lists, fenced code blocks (` ``` `), blockquotes (`>`),
/// horizontal rules (`---`), task lists (`- [x]` / `- [ ]`) and paragraphs.
/// Inline syntax (bold, italic, code, links) is delegated to
/// `AttributedString(markdown:)`.
///
/// Pre-processes platform-specific extensions before parsing:
/// - `:emoji:` shortcodes (GitHub / GitLab) → unicode emoji
/// - `<details>` / `<summary>` blocks → headings + body
/// - Stripped non-semantic HTML (`<br>`, `<sub>`, `<sup>`, `<kbd>`, `<picture>`, …)
///
/// Not a full CommonMark renderer — tables, nested lists, and images aren't
/// supported. Good enough for typical PR descriptions; richer rendering can
/// follow a real markdown library later.
struct MarkdownView: View {
    let source: String

    @Environment(\.appTheme) private var theme
    @ObservedObject private var emojiStore = EmojiShortcodeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            ForEach(Array(MarkdownView.parse(source, emojiMap: emojiStore.map).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(AppFont.sans(headingSize(level), weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
                .padding(.top, level == 1 ? 4 : 0)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            Text(inlineAttributed(text))
                .font(AppFont.sans(12.5))
                .foregroundStyle(theme.palette.fg1)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .blockquote(let lines):
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Rectangle().fill(theme.palette.fg4).frame(width: 3)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, text in
                        Text(inlineAttributed(text))
                            .font(AppFont.sans(12.5))
                            .foregroundStyle(theme.palette.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                        marker(ordered: ordered, index: idx, item: item)
                        Text(inlineAttributed(displayText(of: item)))
                            .font(AppFont.sans(12.5))
                            .foregroundStyle(theme.palette.fg1)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .codeBlock(let language, let body):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(AppFont.mono(10, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)
                }
                ScrollView(.horizontal) {
                    Text(body)
                        .font(AppFont.mono(11.5, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .textSelection(.enabled)
                        .padding(DesignTokens.Spacing.md)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(theme.palette.bg2))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))

        case .horizontalRule:
            Rectangle()
                .fill(theme.palette.line)
                .frame(height: DesignTokens.Stroke.regular)
                .padding(.vertical, DesignTokens.Spacing.xs)
        }
    }

    @ViewBuilder
    private func marker(ordered: Bool, index: Int, item: ListItem) -> some View {
        let p = theme.palette
        switch item {
        case .plain:
            Text(ordered ? "\(index + 1)." : "•")
                .font(AppFont.sans(12.5))
                .foregroundStyle(p.fg3)
                .frame(width: DesignTokens.IconSize.xl, alignment: .trailing)
        case .task(let checked, _):
            Text(checked ? "☑" : "☐")
                .font(AppFont.sans(13))
                .foregroundStyle(checked ? p.ok : p.fg3)
                .frame(width: DesignTokens.IconSize.xl, alignment: .trailing)
        }
    }

    private func displayText(of item: ListItem) -> String {
        switch item {
        case .plain(let text): return text
        case .task(_, let text): return text
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 17
        case 2:  return 15
        default: return 13
        }
    }

    private func inlineAttributed(_ raw: String) -> AttributedString {
        var attr: AttributedString
        if let parsed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            attr = parsed
        } else {
            attr = AttributedString(raw)
        }
        for run in attr.runs where run.link != nil {
            attr[run.range].foregroundColor = theme.palette.accent
        }
        return attr
    }

    // MARK: - Block model

    enum ListItem: Equatable {
        case plain(String)
        case task(checked: Bool, text: String)
    }

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case blockquote([String])
        case list(ordered: Bool, items: [ListItem])
        case codeBlock(language: String?, body: String)
        case horizontalRule
    }

    // MARK: - Preprocessing

    /// Cleans up provider-specific extensions before block parsing so the
    /// parser can stay close to plain CommonMark.
    static func preprocess(_ source: String, emojiMap: [String: String] = [:]) -> String {
        var s = source.replacingOccurrences(of: "\r\n", with: "\n")

        // Replace `<summary>...</summary>` with a markdown heading so the
        // collapsible section title is visible. Done before generic HTML
        // stripping because `<summary>` carries semantic meaning.
        s = replaceMatches(in: s, pattern: #"(?is)<summary[^>]*>(.*?)</summary>"#) { match in
            "\n\n## \(match.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }

        // `<br>` / `<br/>` → newline so paragraph layout still works
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)

        // Drop opening + closing tags but keep their contents. Targets the
        // structural / decorative tags PR templates tend to wrap stuff in.
        let droppableTags = ["details", "div", "span", "sub", "sup", "kbd",
                             "picture", "figure", "figcaption", "section", "article", "p"]
        for tag in droppableTags {
            s = s.replacingOccurrences(
                of: "(?is)</?\(tag)[^>]*>",
                with: "",
                options: .regularExpression
            )
        }

        // Convert task list items so they survive the inline-markdown parser.
        // `- [x]` / `- [X]` → checked, `- [ ]` → unchecked. We use a unique
        // sentinel that the block parser then turns into `.task` items.
        s = s.replacingOccurrences(
            of: #"(?m)^(\s*)[-*]\s+\[[xX]\]\s+"#,
            with: "$1- ✅TASK_DONE✅ ",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(?m)^(\s*)[-*]\s+\[\s\]\s+"#,
            with: "$1- ⬜TASK_TODO⬜ ",
            options: .regularExpression
        )

        // Emoji shortcodes — driven by the shared store, which mirrors
        // GitHub's `/emojis` endpoint. Unknown shortcodes fall through.
        if !emojiMap.isEmpty {
            s = replaceEmojiShortcodes(in: s, map: emojiMap)
        }

        return s
    }

    private static func replaceMatches(in source: String,
                                       pattern: String,
                                       transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }
        let nsSource = source as NSString
        var result = ""
        var lastEnd = 0
        let range = NSRange(location: 0, length: nsSource.length)
        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let outer = match.range(at: 0)
            let inner = match.range(at: 1)
            result += nsSource.substring(with: NSRange(location: lastEnd, length: outer.location - lastEnd))
            result += transform(nsSource.substring(with: inner))
            lastEnd = outer.location + outer.length
        }
        result += nsSource.substring(with: NSRange(location: lastEnd, length: nsSource.length - lastEnd))
        return result
    }

    /// Walks the source once and replaces every well-formed `:shortcode:`
    /// with the matching unicode emoji. Direct character scan rather than
    /// regex — avoids ICU lookbehind quirks and handles all valid shortcode
    /// names (alphanumerics + `_` `+` `-`).
    private static func replaceEmojiShortcodes(in source: String, map: [String: String]) -> String {
        guard !map.isEmpty, source.contains(":") else { return source }
        var result = ""
        result.reserveCapacity(source.count)

        let chars = Array(source)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            // A shortcode opens on `:` only when the preceding char isn't
            // alphanumeric or `/` (so URLs and `_word:` survive).
            if char == ":" {
                let precededByID: Bool = {
                    guard index > 0 else { return false }
                    let prev = chars[index - 1]
                    return prev.isLetter || prev.isNumber || prev == "_" || prev == "/"
                }()
                if !precededByID {
                    if let (name, end) = readShortcode(chars: chars, start: index) {
                        if let emoji = map[name.lowercased()] {
                            result += emoji
                            index = end + 1
                            continue
                        }
                    }
                }
            }
            result.append(char)
            index += 1
        }
        return result
    }

    /// Returns the shortcode name (between colons) and the index of the
    /// closing colon if there is one within a sane lookahead. `start` points
    /// to the opening `:`.
    private static func readShortcode(chars: [Character], start: Int) -> (name: String, end: Int)? {
        var name = ""
        var i = start + 1
        // Cap at 60 chars — shortcodes are short; longer scans are noise.
        let limit = min(chars.count, start + 60)
        while i < limit {
            let c = chars[i]
            if c == ":" {
                guard !name.isEmpty else { return nil }
                return (name, i)
            }
            if c.isLetter || c.isNumber || c == "_" || c == "+" || c == "-" {
                name.append(c)
                i += 1
            } else {
                return nil
            }
        }
        return nil
    }

    // MARK: - Block parser

    static func parse(_ source: String, emojiMap: [String: String] = [:]) -> [Block] {
        let prepared = preprocess(source, emojiMap: emojiMap)
        let lines = prepared.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var blocks: [Block] = []
        var index = 0
        var paragraphBuffer: [String] = []
        var listBuffer: [ListItem] = []
        var listOrdered = false
        var quoteBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let text = paragraphBuffer.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraphBuffer.removeAll()
        }

        func flushList() {
            guard !listBuffer.isEmpty else { return }
            blocks.append(.list(ordered: listOrdered, items: listBuffer))
            listBuffer.removeAll()
        }

        func flushQuote() {
            guard !quoteBuffer.isEmpty else { return }
            blocks.append(.blockquote(quoteBuffer))
            quoteBuffer.removeAll()
        }

        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        while index < lines.count {
            let line = lines[index]
            let stripped = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if stripped.hasPrefix("```") {
                flushAll()
                let lang = String(stripped.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let inner = lines[index]
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    body.append(inner)
                    index += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang,
                                         body: body.joined(separator: "\n")))
                continue
            }

            // Blank line: flush in-flight buffers
            if stripped.isEmpty {
                flushAll()
                index += 1
                continue
            }

            // Horizontal rule
            if stripped.count >= 3,
               (stripped.allSatisfy({ $0 == "-" }) ||
                stripped.allSatisfy({ $0 == "*" }) ||
                stripped.allSatisfy({ $0 == "_" })) {
                flushAll()
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Heading
            if let heading = parseHeading(stripped) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Blockquote (collect consecutive `> ` lines)
            if stripped.hasPrefix("> ") || stripped == ">" {
                flushParagraph()
                flushList()
                let body = stripped == ">" ? "" : String(stripped.dropFirst(2))
                quoteBuffer.append(body)
                index += 1
                continue
            }

            // Task list item (sentinels were inserted in preprocess)
            if stripped.hasPrefix("- ✅TASK_DONE✅ ") {
                flushParagraph()
                flushQuote()
                if listOrdered { flushList() }
                listOrdered = false
                let text = String(stripped.dropFirst("- ✅TASK_DONE✅ ".count))
                listBuffer.append(.task(checked: true, text: text))
                index += 1
                continue
            }
            if stripped.hasPrefix("- ⬜TASK_TODO⬜ ") {
                flushParagraph()
                flushQuote()
                if listOrdered { flushList() }
                listOrdered = false
                let text = String(stripped.dropFirst("- ⬜TASK_TODO⬜ ".count))
                listBuffer.append(.task(checked: false, text: text))
                index += 1
                continue
            }

            // Unordered list
            if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") {
                flushParagraph()
                flushQuote()
                if listOrdered { flushList() }
                listOrdered = false
                listBuffer.append(.plain(String(stripped.dropFirst(2))))
                index += 1
                continue
            }

            // Ordered list
            if let item = parseOrderedListItem(stripped) {
                flushParagraph()
                flushQuote()
                if !listOrdered { flushList() }
                listOrdered = true
                listBuffer.append(.plain(item))
                index += 1
                continue
            }

            // Plain paragraph line
            flushList()
            flushQuote()
            paragraphBuffer.append(stripped)
            index += 1
        }
        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
            if level > 6 { return nil }
        }
        guard level > 0 else { return nil }
        let rest = String(line.dropFirst(level))
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseOrderedListItem(_ line: String) -> String? {
        var digits = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty, idx < line.endIndex, line[idx] == "." else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        return String(line[line.index(after: idx)...])
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let sample = """
    <details>
    <summary>:rocket: Información tabla</summary>

    Some intro paragraph spanning multiple lines that should
    wrap into a single paragraph in the rendered output.

    ## :clipboard: Descripción

    Adds the **PR/MR** integration with `Phase 2` detail view.

    Tipo de Mantto:
    - [x] Preventivo
    - [x] Inspección
    - [ ] Correctivo

    Tipos distintos:
    - [ ] Marca
    - [ ] Modelo
    - [x] N. serie

    > Importante: revisar antes de mergear.

    ```swift
    func hello() -> String {
        return "world"
    }
    ```

    ---

    Final paragraph with [link](https://example.com).
    </details>
    """
    ScrollView {
        MarkdownView(source: sample)
            .padding(DesignTokens.Spacing.huge)
    }
    .frame(width: 600, height: 800)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
