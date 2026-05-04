import Foundation
import os

actor RepositoryStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "store")

    private let fileURL: URL
    private(set) var repositories: [Repository] = []

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("recents.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            repositories = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            repositories = try decoder.decode([Repository].self, from: data)
            sort()
        } catch {
            Self.logger.error("Failed to load recents.json: \(error.localizedDescription, privacy: .public)")
            repositories = []
        }
    }

    @discardableResult
    func touch(_ url: URL) -> [Repository] {
        if let index = repositories.firstIndex(where: { $0.url == url }) {
            repositories[index].lastOpenedAt = .now
        } else {
            repositories.append(Repository(url: url))
        }
        sort()
        persist()
        return repositories
    }

    @discardableResult
    func remove(_ url: URL) -> [Repository] {
        repositories.removeAll { $0.url == url }
        persist()
        return repositories
    }

    private func sort() {
        repositories.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(repositories)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist recents.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
