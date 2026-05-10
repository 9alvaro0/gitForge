import Foundation

extension GitProfile {
    static let previewPersonal = GitProfile(
        name: "Personal",
        userName: "Alvaro Guerra",
        userEmail: "9alvaro0@gmail.com",
        signingKey: nil
    )
    static let previewWork = GitProfile(
        name: "Mercadona",
        userName: "Alvaro Guerra",
        userEmail: "alvaro.guerra@mercadona.es",
        signingKey: "ABCD1234DEADBEEF"
    )
    static let previewSamples: [GitProfile] = [.previewPersonal, .previewWork]
}

extension RepoIdentity {
    static let previewLocalWork = RepoIdentity(
        name: "Alvaro Guerra",
        email: "alvaro.guerra@mercadona.es",
        signingKey: nil,
        isLocal: true
    )
    static let previewInheritedPersonal = RepoIdentity(
        name: "Alvaro Guerra",
        email: "9alvaro0@gmail.com",
        signingKey: nil,
        isLocal: false
    )
}
