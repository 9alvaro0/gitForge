import SwiftUI
import AppKit

extension EnvironmentValues {
    /// The open repository's author avatars (#65). `nil` (previews, sheets
    /// outside a repository) draws initials only.
    @Entry var authorAvatars: AuthorAvatarStore? = nil
}

/// A commit author's avatar: initials on their colour (`AuthorMonogram`)
/// right away, replaced by the picture the repository's host returns when it
/// has a connected account (`AuthorAvatarStore`). Asks only once it has been
/// on screen briefly, so scrolling past a row requests nothing.
///
/// VoiceOver reads the author's name. Where the name is already spoken next
/// to it, the caller hides the avatar or folds it into one element.
struct AuthorAvatar: View {
    let author: CommitAuthor
    /// A commit by `author`: GitHub finds the account through it. `nil`
    /// draws initials only.
    let sha: String?
    var size: CGFloat = 18

    @Environment(\.authorAvatars) private var store
    @State private var loaded: Loaded?

    /// The picture for one email, so a reused view never shows the previous author's.
    private struct Loaded {
        let email: String
        let image: NSImage
    }

    /// How long the avatar must stay on screen before it asks the host.
    static let settleDelay: Duration = .milliseconds(150)

    private var email: String { author.normalizedEmail }

    var body: some View {
        ZStack {
            if let image = shownImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Avatar(name: author.name, size: size, colorSeed: AuthorMonogram.colorSeed(name: author.name, email: author.email))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: author.displayName))
        .task(id: TaskKey(email: email, sha: sha, hasStore: store != nil)) { await load() }
    }

    /// What the task is about: a new author, commit or store asks again.
    private struct TaskKey: Hashable {
        let email: String
        let sha: String?
        let hasStore: Bool
    }

    /// The loaded picture for this author, else one already in memory (a row
    /// scrolled back into view shows it on its first frame).
    private var shownImage: NSImage? {
        if let loaded, loaded.email == email { return loaded.image }
        guard let data = store?.cachedImage(for: email) else { return nil }
        return AvatarImageCache.image(for: email, data: data)
    }

    private func load() async {
        guard let store, let sha, !email.isEmpty else { return }
        if loaded?.email == email { return }
        if let data = store.cachedImage(for: email) {
            if let image = AvatarImageCache.image(for: email, data: data) { loaded = Loaded(email: email, image: image) }
            return
        }
        guard store.mayLoad else { return }
        try? await Task.sleep(for: Self.settleDelay)
        guard !Task.isCancelled else { return }
        let requested = email
        guard let data = await store.image(email: requested, sha: sha), !Task.isCancelled,
              let image = AvatarImageCache.image(for: requested, data: data) else { return }
        loaded = Loaded(email: requested, image: image)
    }
}

/// Decoded avatars, so a row re-rendering (hover, selection) doesn't decode
/// its picture again. Keyed by email and the data's size and hash: a
/// refreshed picture replaces the old one.
@MainActor
enum AvatarImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    static func image(for email: String, data: Data) -> NSImage? {
        let key = "\(email)|\(data.count)|\(data.hashValue)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: Spacing.s8) {
        AuthorAvatar(author: CommitAuthor(name: "Ana Pérez", email: "ana@forge.dev"), sha: nil, size: 16)
        AuthorAvatar(author: CommitAuthor(name: "Luis", email: "luis@forge.dev"), sha: nil, size: 22)
        AuthorAvatar(author: CommitAuthor(name: "", email: "ci@forge.dev"), sha: nil, size: 22)
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
