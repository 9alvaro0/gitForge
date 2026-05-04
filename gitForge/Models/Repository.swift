import Foundation

nonisolated struct Repository: Sendable, Equatable, Identifiable, Codable {
    var url: URL
    var lastOpenedAt: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var path: String { url.path(percentEncoded: false) }

    init(url: URL, lastOpenedAt: Date = .now) {
        self.url = url
        self.lastOpenedAt = lastOpenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        self.url = URL(fileURLWithPath: path)
        self.lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url.path(percentEncoded: false), forKey: .path)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    }
}
