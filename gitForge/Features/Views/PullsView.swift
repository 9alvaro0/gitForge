import SwiftUI

/// `.gf-view-pulls` — pull request list + detail.
struct PullsView: View {
    let pulls: [PullRequest]

    @Environment(\.appTheme) private var theme

    enum Tab: String, CaseIterable, Hashable { case open, merged, all }

    @State private var tab: Tab = .open
    @State private var selectedId: Int?

    init(pulls: [PullRequest] = PullRequest.previewSamples) {
        self.pulls = pulls
        _selectedId = State(initialValue: pulls.first?.id)
    }

    private var filtered: [PullRequest] {
        switch tab {
        case .open:   return pulls.filter { $0.status == .open || $0.status == .review }
        case .merged: return pulls.filter { $0.status == .merged }
        case .all:    return pulls
        }
    }

    private var selected: PullRequest? {
        guard let id = selectedId else { return filtered.first }
        return pulls.first { $0.id == id } ?? filtered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Pull requests") {
                EmptyView()
            } right: {
                SegmentedControl<Tab>(
                    [(.open, "Open"), (.merged, "Merged"), (.all, "All")],
                    selection: $tab
                )
                ToolButton(.plus, label: "New PR", primary: true, disabled: true) { }
            }
            HStack(spacing: 0) {
                listColumn
                detailColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var listColumn: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filtered) { pr in
                    Button(action: { selectedId = pr.id }) {
                        PullRequestRow(pr: pr, selected: selectedId == pr.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: DesignTokens.Pulls.listWidth)
        .background(theme.palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.palette.lineStrong).frame(width: 1) }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let pr = selected {
            ScrollView {
                PullRequestDetail(pr: pr)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyState(icon: .pr, title: "Select a pull request", subtitle: nil) { EmptyView() }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullsView(pulls: PullRequest.previewSamples)
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}

private struct PullRequestRow: View {
    let pr: PullRequest
    let selected: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusGlyph
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title)
                    .font(AppFont.sans(12.5, weight: .medium))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                Text("#\(pr.id) · \(pr.author) · \(pr.branch) → \(pr.target) · \(pr.when)")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                    .lineLimit(1)
            }
            VStack(alignment: .trailing, spacing: 4) {
                checksGlyph
                Text("\(pr.reviews)/2")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.palette.bg4 : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    private var statusGlyph: some View {
        Group {
            switch pr.status {
            case .open:   Circle().stroke(theme.palette.ok, lineWidth: 1.5).frame(width: 12, height: 12)
            case .review: Circle().fill(theme.palette.mod).frame(width: 12, height: 12)
            case .merged: Image(systemName: "diamond.fill").foregroundStyle(theme.palette.accent)
            case .closed: GFIcon(kind: .x, size: 12, stroke: theme.palette.del)
            }
        }
    }

    private var checksGlyph: some View {
        Group {
            switch pr.checks {
            case .pass:    Text("✓").foregroundStyle(theme.palette.ok)
            case .running: Circle().fill(theme.palette.mod).frame(width: 8, height: 8)
            case .fail:    Text("✕").foregroundStyle(theme.palette.del)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

private struct PullRequestDetail: View {
    let pr: PullRequest
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text(pr.status.rawValue.capitalized)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(statusColor)
                Text(pr.title).font(AppFont.sans(14, weight: .semibold)).foregroundStyle(theme.palette.fg1)
                Text("#\(pr.id)").font(AppFont.mono(12, family: theme.monoFont)).foregroundStyle(theme.palette.fg3)
            }
            HStack(spacing: 6) {
                Avatar(name: pr.author, size: 18)
                Text("\(pr.author) wants to merge").font(AppFont.sans(12)).foregroundStyle(theme.palette.fg2)
                Pill(text: pr.branch, kind: .up)
                Text("into").foregroundStyle(theme.palette.fg2)
                Pill(text: pr.target, kind: .clean)
            }

            section(title: "Checks") {
                checkRow(name: "lint", status: .pass, time: "2m 14s")
                checkRow(name: "test:unit", status: .pass, time: "4m 02s")
                checkRow(name: "test:e2e", status: .running, time: "2m 18s")
                checkRow(name: "build", status: .pass, time: "1m 42s")
            }

            section(title: "Reviewers") {
                reviewerRow(name: "L. Park", approved: true)
                reviewerRow(name: "R. Tanaka", approved: false)
            }

            HStack(spacing: 8) {
                GFButton(title: "Add review", disabled: true) { }
                GFButton(title: "Checkout PR", disabled: true) { }
                GFButton(title: "Merge", style: .primary, disabled: true) { }
            }
            Text("Pull-request actions need a host backend (GitHub/GitLab). Mock data shown for now.")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
        }
    }

    private var statusColor: Color {
        switch pr.status {
        case .open:   return theme.palette.ok
        case .review: return theme.palette.mod
        case .merged: return theme.palette.accent
        case .closed: return theme.palette.del
        }
    }

    @ViewBuilder
    private func section<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            content()
        }
    }

    @ViewBuilder
    private func checkRow(name: String, status: PullRequest.Checks, time: String) -> some View {
        HStack(spacing: 10) {
            switch status {
            case .pass:    Text("✓").foregroundStyle(theme.palette.ok)
            case .running: Circle().fill(theme.palette.mod).frame(width: 8, height: 8)
            case .fail:    Text("✕").foregroundStyle(theme.palette.del)
            }
            Text(name).font(AppFont.mono(12, family: theme.monoFont)).foregroundStyle(theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(time).font(AppFont.mono(11, family: theme.monoFont)).foregroundStyle(theme.palette.fg3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func reviewerRow(name: String, approved: Bool) -> some View {
        HStack(spacing: 10) {
            Avatar(name: name, size: 20)
            Text(name).font(AppFont.sans(12)).foregroundStyle(theme.palette.fg1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Pill(text: approved ? "✓ approved" : "pending", kind: approved ? .clean : .dirty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.palette.line, lineWidth: 1))
    }
}
