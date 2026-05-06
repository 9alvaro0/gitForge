import Foundation

enum RepositoryTab: String, CaseIterable, Identifiable, Sendable {
    case history
    case changes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .changes: "Changes"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .changes: "pencil.line"
        }
    }
}
