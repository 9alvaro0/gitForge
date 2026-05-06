import SwiftUI

/// `.gf-status-tag` — A/M/D/?/etc. small badge.
struct StatusTag: View {
    enum Kind { case added, modified, deleted, untracked, renamed, copied, typeChanged, unmerged, ignored }

    let kind: Kind

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(letter)
            .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
            .frame(width: 18, height: 18)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.18)))
    }

    private var letter: String {
        switch kind {
        case .added:        return "A"
        case .modified:     return "M"
        case .deleted:      return "D"
        case .untracked:    return "?"
        case .renamed:      return "R"
        case .copied:       return "C"
        case .typeChanged:  return "T"
        case .unmerged:     return "U"
        case .ignored:      return "!"
        }
    }
    private var color: Color {
        switch kind {
        case .added:        return theme.palette.add
        case .modified:     return theme.palette.mod
        case .deleted:      return theme.palette.del
        case .untracked:    return theme.palette.fg3
        case .renamed:      return theme.palette.info
        case .copied:       return theme.palette.info
        case .typeChanged:  return theme.palette.mod
        case .unmerged:     return theme.palette.del
        case .ignored:      return theme.palette.fg4
        }
    }
}

extension StatusTag.Kind {
    init(workingFile: WorkingCopyFile.Status) {
        switch workingFile {
        case .modified, .typeChanged: self = .modified
        case .added:                  self = .added
        case .deleted:                self = .deleted
        case .renamed:                self = .renamed
        case .copied:                 self = .copied
        case .untracked:              self = .untracked
        case .unmerged:               self = .unmerged
        case .ignored:                self = .ignored
        case .unmodified:             self = .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: 8) {
        StatusTag(kind: .added)
        StatusTag(kind: .modified)
        StatusTag(kind: .deleted)
        StatusTag(kind: .untracked)
        StatusTag(kind: .renamed)
        StatusTag(kind: .copied)
        StatusTag(kind: .typeChanged)
        StatusTag(kind: .unmerged)
        StatusTag(kind: .ignored)
    }
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
