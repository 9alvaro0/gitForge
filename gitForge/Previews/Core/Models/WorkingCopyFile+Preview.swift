import Foundation

extension WorkingCopyFile {
    static let previewSamples: [WorkingCopyFile] = [
        WorkingCopyFile(
            path: "Sources/Foo.swift",
            stagedStatus: .modified, unstagedStatus: .unmodified,
            originalPath: nil
        ),
        WorkingCopyFile(
            path: "README.md",
            stagedStatus: .unmodified, unstagedStatus: .modified,
            originalPath: nil
        ),
        WorkingCopyFile(
            path: "Sources/Features/NewView.swift",
            stagedStatus: .unmodified, unstagedStatus: .untracked,
            originalPath: nil
        ),
        WorkingCopyFile(
            path: "Sources/Features/Repository/Renamed.swift",
            stagedStatus: .renamed, unstagedStatus: .unmodified,
            originalPath: "Sources/Old/Path.swift"
        ),
    ]
}
