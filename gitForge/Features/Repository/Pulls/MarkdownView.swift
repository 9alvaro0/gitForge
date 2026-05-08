import SwiftUI
import Textual

/// PR/MR description renderer. Thin wrapper over Textual's `StructuredText`
/// that wires the document into our `AppTheme` (palette + typography +
/// accent-tinted links). Textual handles full CommonMark + GFM (headings,
/// lists, tables, blockquotes, code blocks, task lists, autolinks) so we
/// don't maintain a parser of our own.
struct MarkdownView: View {
    let source: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        StructuredText(markdown: source)
            .font(AppFont.sans(12.5))
            .foregroundStyle(theme.palette.fg1)
            .tint(theme.palette.accent)
            .textual.textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let sample = """
    ## Description

    Adds the **PR/MR** integration with `Phase 2` detail view.

    Tipo de Mantto:
    - [x] Preventivo
    - [x] Inspección
    - [ ] Correctivo

    > Importante: revisar antes de mergear.

    ```swift
    func hello() -> String {
        return "world"
    }
    ```

    | Column A | Column B |
    | -------- | -------- |
    | one      | two      |
    | three    | four     |

    ---

    Final paragraph with [link](https://example.com).
    """
    ScrollView {
        MarkdownView(source: sample)
            .padding(DesignTokens.Spacing.huge)
    }
    .frame(width: 600, height: 800)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
