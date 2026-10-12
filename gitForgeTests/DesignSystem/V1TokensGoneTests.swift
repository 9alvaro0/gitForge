import Foundation
import Testing

/// Redesign spec §1, criterion 2: everything comes from v2 tokens. Fails if
/// any source file uses the v1 design system again.
@Suite("No v1 design tokens left")
struct V1TokensGoneTests {
    static let patterns = ["FontSize.", "DesignTokens.", "theme.palette", "GFIcon", "AppFont.sans", "AppFont.mono"]

    /// `<repo>/gitForge`, found from this file's path.
    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DesignSystem
            .deletingLastPathComponent()   // gitForgeTests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("gitForge")
    }

    @Test("No source file uses FontSize, DesignTokens, theme.palette, GFIcon or AppFont.sans/mono",
          .disabled("until F9 task 4 removes the v1 design system"))
    func noV1() throws {
        let enumerator = try #require(FileManager.default.enumerator(at: Self.sourceRoot, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let hits = Self.patterns.filter { text.contains($0) }
            if !hits.isEmpty {
                offenders.append("\(url.path.replacingOccurrences(of: Self.sourceRoot.path + "/", with: "")): \(hits.joined(separator: ", "))")
            }
        }
        #expect(offenders.isEmpty, "v1 tokens in:\n\(offenders.sorted().joined(separator: "\n"))")
    }
}
