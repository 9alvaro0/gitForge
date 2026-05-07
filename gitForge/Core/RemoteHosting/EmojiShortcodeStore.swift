import Foundation
import Combine
import os
import SwiftUI

/// Caches the canonical `:shortcode: → emoji` map served by GitHub at
/// `https://api.github.com/emojis`. The same shortcodes are used by GitLab,
/// so this single source of truth covers both providers without us having to
/// maintain a hand-curated list.
///
/// Lifecycle:
/// 1. App boot → `loadCachedSync()` reads the on-disk cache (instant, no I/O
///    on the network) so the first markdown render already has the map.
/// 2. App boot → `refreshIfNeeded()` fires off a background fetch when the
///    cache is missing or stale.
/// 3. `MarkdownView` observes this object so it re-renders the moment a fresh
///    map lands.
@MainActor
final class EmojiShortcodeStore: ObservableObject {
    static let shared = EmojiShortcodeStore()

    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "emoji")
    private static let refreshInterval: TimeInterval = 60 * 60 * 24 * 30 // 30 days

    // emojibase covers ~5000 shortcodes including CLDR-style names like
    // `camera_with_flash` that GitHub's `/emojis` aliases away. The GitHub
    // endpoint is fetched second to fill in GitHub-specific aliases like
    // `tada`, `white_check_mark`, `camera_flash`, etc.
    private static let emojibaseEndpoint = URL(string: "https://cdn.jsdelivr.net/npm/emojibase-data@latest/en/shortcodes/emojibase.json")!
    private static let githubEndpoint = URL(string: "https://api.github.com/emojis")!

    @Published private(set) var map: [String: String] = [:]
    private var lastRefreshAt: Date?

    private let cacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("com.warwarelabs.gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("emoji-shortcodes.json")
    }()

    private struct Cache: Codable {
        var map: [String: String]
        var fetchedAt: Date
    }

    /// Loads the on-disk cache synchronously. Cheap I/O and only runs once at
    /// startup. Failure is silent — the network refresh will populate.
    func loadCachedSync() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        self.map = cache.map
        self.lastRefreshAt = cache.fetchedAt
    }

    /// Refreshes the map from GitHub when the cache is empty or older than
    /// `refreshInterval`. Idempotent — safe to call multiple times.
    func refreshIfNeeded() async {
        if let last = lastRefreshAt, Date().timeIntervalSince(last) < Self.refreshInterval, !map.isEmpty {
            return
        }
        await refreshFromNetwork()
    }

    func refreshFromNetwork() async {
        // Fire both fetches in parallel — they hit different CDNs and have
        // different aliases so we always want the merged result.
        async let emojibaseMap = Self.fetchEmojibase()
        async let githubMap = Self.fetchGitHub()

        var merged = await emojibaseMap
        // Don't let GitHub overwrite emojibase entries (CLDR names are more
        // standard); GitHub fills in any aliases emojibase doesn't have.
        for (key, value) in await githubMap where merged[key] == nil {
            merged[key] = value
        }

        guard !merged.isEmpty else {
            Self.logger.warning("Emoji refresh produced empty map; cache untouched")
            return
        }

        let cache = Cache(map: merged, fetchedAt: .now)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: [.atomic])
        }
        self.map = merged
        self.lastRefreshAt = .now
        Self.logger.info("Emoji map refreshed (\(merged.count, privacy: .public) entries)")
    }

    // MARK: - Sources

    /// emojibase preset → 5000+ shortcodes including CLDR aliases. Each
    /// `hexcode` is either a single hex codepoint or a sequence joined with
    /// `-`. Values are either a single shortcode string or an array.
    private static func fetchEmojibase() async -> [String: String] {
        var request = URLRequest(url: emojibaseEndpoint)
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                logger.warning("emojibase fetch non-2xx")
                return [:]
            }
            // Decode as `Any` because values may be String or [String].
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("emojibase fetch malformed JSON")
                return [:]
            }
            var map: [String: String] = [:]
            for (hex, codes) in raw {
                guard let emoji = unicodeEmoji(fromHex: hex) else { continue }
                if let single = codes as? String {
                    map[single] = emoji
                } else if let list = codes as? [String] {
                    for code in list { map[code] = emoji }
                }
            }
            return map
        } catch {
            logger.warning("emojibase fetch failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// GitHub `/emojis` → shortcode → URL. We extract the unicode codepoints
    /// from the URL path. Custom (non-unicode) GitHub emojis are skipped.
    private static func fetchGitHub() async -> [String: String] {
        var request = URLRequest(url: githubEndpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                logger.warning("GitHub /emojis non-2xx")
                return [:]
            }
            let raw = try JSONDecoder().decode([String: String].self, from: data)
            var map: [String: String] = [:]
            for (shortcode, urlString) in raw {
                if let emoji = unicodeEmoji(fromURL: urlString) {
                    map[shortcode] = emoji
                }
            }
            return map
        } catch {
            logger.warning("GitHub emojis fetch failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// Converts a hex codepoint (or `-`-joined sequence) into the matching
    /// unicode string. e.g. `"1F4F8"` → `"📸"`, `"1F1EA-1F1F8"` → `"🇪🇸"`.
    private static func unicodeEmoji(fromHex hex: String) -> String? {
        let scalars = hex.split(separator: "-")
            .compactMap { UInt32($0, radix: 16) }
            .compactMap { UnicodeScalar($0) }
        guard !scalars.isEmpty else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Extracts the unicode emoji from a github asset URL like
    /// `https://github.githubassets.com/images/icons/emoji/unicode/1f680.png`.
    /// Returns nil for non-unicode assets (e.g. `…/emoji/shipit.png`).
    private static func unicodeEmoji(fromURL urlString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"/unicode/([0-9a-f-]+)\.png"#),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
              let hexRange = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return unicodeEmoji(fromHex: String(urlString[hexRange]))
    }
}
