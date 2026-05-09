import Foundation

extension GitIdentity {
    /// Stand-in identity used by sidebar / settings previews. `.unknown` is
    /// already on the type itself for the "no name configured" state.
    static let preview = GitIdentity(name: "Alvaro Guerra", email: "9alvaro0@gmail.com")
}
