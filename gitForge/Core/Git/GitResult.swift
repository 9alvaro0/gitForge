import Foundation

nonisolated struct GitResult: Sendable, Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let duration: TimeInterval

    var isSuccess: Bool { exitCode == 0 }
}
