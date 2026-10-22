import Foundation
import Sparkle

/// What the What's New sheet shows: one or more releases, newest first.
nonisolated struct WhatsNewPresentation: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// First launch of a version with highlights.
        case launch
        /// Help › What's New in gitForge.
        case menu
    }

    let id = UUID()
    let currentVersion: String
    /// The version whose notes were last shown, when known.
    let previousVersion: String?
    let releases: [WhatsNewRelease]
    let source: Source

    /// Releases that bring highlights, each shown as its own group.
    var highlightGroups: [WhatsNewRelease] {
        releases.filter { !$0.highlights.isEmpty }
    }

    /// Fixes and improvements of every release, for the "And also" block.
    var alsoItems: [LocalizedText] {
        releases.flatMap { $0.fixes + $0.improvements }
    }

    var releaseNotesURL: URL {
        URL(string: "https://github.com/9alvaro0/gitForge/releases/tag/v\(currentVersion)")!
    }
}

/// Decides whether this launch shows What's New, and remembers the newest
/// version whose notes the user has seen.
nonisolated struct WhatsNewGate {
    static let lastSeenKey = "gitForge.whatsNew.lastSeenVersion"
    /// Written by `RootView` when onboarding finishes.
    static let onboardingCompletedKey = "gitForge.onboarding.completed"
    /// Sparkle's ordering, the one the updater already uses, plus a tie-break
    /// Sparkle lacks: it reads "1.4.0-beta.1" and "1.4.0" as equal, and a
    /// semver prerelease comes before its release.
    static let sparkleCompare: WhatsNewVersionCompare = { lhs, rhs in
        let result = SUStandardVersionComparator.default.compareVersion(lhs, toVersion: rhs)
        guard result == .orderedSame, lhs != rhs else { return result }
        let lhsIsPrerelease = lhs.contains("-")
        let rhsIsPrerelease = rhs.contains("-")
        if lhsIsPrerelease != rhsIsPrerelease {
            return lhsIsPrerelease ? .orderedAscending : .orderedDescending
        }
        return lhs.compare(rhs, options: .numeric)
    }

    static var standard: WhatsNewGate {
        WhatsNewGate(defaults: .standard, compare: sparkleCompare)
    }

    let defaults: UserDefaults
    let compare: WhatsNewVersionCompare

    init(defaults: UserDefaults, compare: @escaping WhatsNewVersionCompare) {
        self.defaults = defaults
        self.compare = compare
    }

    var lastSeenVersion: String? {
        defaults.string(forKey: Self.lastSeenKey)
    }

    /// The releases to show on this launch, or `nil`. When nothing is shown
    /// the version is marked seen right away; otherwise it is marked when
    /// the sheet is presented (`markSeen`).
    func evaluate(currentVersion: String, catalog: WhatsNewCatalog) -> WhatsNewPresentation? {
        let lastSeen = lastSeenVersion
        let releases: [WhatsNewRelease]
        if let lastSeen {
            releases = catalog.releases(newerThan: lastSeen, upTo: currentVersion, compare: compare)
        } else if defaults.bool(forKey: Self.onboardingCompletedKey) {
            // Updated from a version that predates What's New: no record of
            // what was seen, so only this version's notes.
            releases = catalog.releases.filter { compare($0.version, currentVersion) == .orderedSame }
        } else {
            // Fresh install: onboarding introduces the app instead.
            releases = []
        }

        guard releases.contains(where: { !$0.highlights.isEmpty }) else {
            markSeen(currentVersion)
            return nil
        }
        return WhatsNewPresentation(currentVersion: currentVersion, previousVersion: lastSeen,
                                    releases: releases, source: .launch)
    }

    /// Records `version` as seen, never lowering what is stored, so going
    /// back to an older build and updating again doesn't repeat the sheet.
    func markSeen(_ version: String) {
        if let stored = lastSeenVersion, compare(stored, version) != .orderedAscending { return }
        defaults.set(version, forKey: Self.lastSeenKey)
    }
}
