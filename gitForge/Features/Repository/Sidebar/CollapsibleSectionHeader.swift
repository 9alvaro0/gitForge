import SwiftUI

struct CollapsibleSectionHeader<Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self._isExpanded = isExpanded
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            trailing()
        }
    }
}
