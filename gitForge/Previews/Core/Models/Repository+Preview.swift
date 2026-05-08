import Foundation

extension Repository {
    static let preview = Repository(
        url: URL(fileURLWithPath: "/Users/preview/Code/gitForge"),
        lastOpenedAt: .now
    )

    static let previewSamples: [Repository] = [
        Repository(
            url: URL(fileURLWithPath: "/Users/preview/Code/gitForge"),
            lastOpenedAt: .now
        ),
        Repository(
            url: URL(fileURLWithPath: "/Users/preview/Code/sandbox-app"),
            lastOpenedAt: .now.addingTimeInterval(-3_600)
        ),
        Repository(
            url: URL(fileURLWithPath: "/Users/preview/Code/website"),
            lastOpenedAt: .now.addingTimeInterval(-86_400)
        ),
    ]
}
