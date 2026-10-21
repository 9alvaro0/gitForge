import Foundation

/// A GitLab release as `major.minor`, from `GET /version` ("17.5.1-ee").
/// Patch and edition don't decide any feature gitForge relies on.
nonisolated struct GitLabVersion: Comparable, Sendable, Hashable {
    let major: Int
    let minor: Int

    init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// `nil` unless the first two dot-separated parts start with digits.
    init?(_ raw: String) {
        let parts = raw.split(separator: ".").prefix(2).compactMap { Int($0.prefix(while: \.isNumber)) }
        guard parts.count == 2 else { return nil }
        self.init(major: parts[0], minor: parts[1])
    }

    static func < (lhs: GitLabVersion, rhs: GitLabVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    /// First release where "Request changes" is on by default (flag
    /// `mr_reviewer_requests_changes` removed in 17.3).
    static let requestChanges = GitLabVersion(major: 17, minor: 3)
}
