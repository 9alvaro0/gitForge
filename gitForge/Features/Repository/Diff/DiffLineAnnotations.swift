import SwiftUI

/// What `DiffPane` draws under some of its lines (review threads), and the
/// "+" that starts a comment on any line of a hunk. Optional: without it
/// the pane looks and behaves as it always has.
struct DiffLineAnnotations {
    /// The lines that have something under them.
    let refs: Set<DiffLineRef>
    /// What goes under a row, given the row's refs that are in `refs`.
    let content: ([DiffLineRef]) -> AnyView
    /// Starts a comment on a line, on the given side. `nil`: no "+".
    var onAddComment: ((DiffLine, DiffSide) -> Void)? = nil

    /// A unified row's refs with something under them (a context line
    /// answers to both sides).
    func matches(_ line: DiffLine) -> [DiffLineRef] {
        DiffLineRef.refs(for: line).filter(refs.contains)
    }

    /// A split row's refs with something under them: the old side from the
    /// left half, the new side from the right, each once.
    func matches(left: DiffLine?, right: DiffLine?) -> [DiffLineRef] {
        let new = right.map(DiffLineRef.refs(for:))?.filter { $0.side == .new } ?? []
        let old = left.map(DiffLineRef.refs(for:))?.filter { $0.side == .old } ?? []
        return (new + old).filter(refs.contains)
    }

    /// The side a split cell comments on: its own, when the line has a
    /// number there.
    static func splitCommentSide(for line: DiffLine?, left: Bool) -> DiffSide? {
        guard let line, line.kind != .noNewline,
              (left ? line.oldLineNumber : line.newLineNumber) != nil else { return nil }
        return left ? .old : .new
    }
}

/// The "+" over a diff row's gutter: shown while the pointer is over the
/// row, and always offered to VoiceOver as an action on the row.
struct DiffRowCommentButton: ViewModifier {
    let onAdd: (() -> Void)?
    /// Where the button sits from the row's leading edge (the sign column).
    let leading: CGFloat

    func body(content: Content) -> some View {
        if let onAdd {
            content.modifier(Hovering(onAdd: onAdd, leading: leading))
        } else {
            content
        }
    }

    private struct Hovering: ViewModifier {
        let onAdd: () -> Void
        let leading: CGFloat

        @Environment(\.appTheme) private var theme
        @State private var hovering = false

        func body(content: Content) -> some View {
            content
                .onHover { hovering = $0 }
                .overlay(alignment: .topLeading) {
                    if hovering {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(theme.colors.accentOnFill)
                                .frame(width: 16, height: 16)
                                .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(theme.colors.accentFill))
                        }
                        .buttonStyle(.plain)
                        .help("Comment on this line")
                        .accessibilityLabel("Comment on this line")
                        .padding(.leading, leading)
                        .padding(.top, 2)
                    }
                }
                .accessibilityAction(named: "Comment on this line", onAdd)
        }
    }
}
