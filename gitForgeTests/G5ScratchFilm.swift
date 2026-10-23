import AppKit
import Foundation
import SwiftUI
import Testing
@testable import gitForge

// SCRATCH: filmstrips of the G5 prototype slide, rendered with the real painter. Never merged.
@Suite("G5 scratch film", .serialized)
@MainActor
struct G5ScratchFilm {
    static let out = ProcessInfo.processInfo.environment["G5_FILM_OUT"] ?? "/tmp/g5film"

    /// The log of the repo at `path` as the History graph loads it, with HEAD on `head`.
    func loadInput(repo path: String, head: String, limit: Int = 200) throws -> GraphInput {
        func git(_ args: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path] + args
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let branches = try git(["for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads"])
            .split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        let log = try git(["log", "--topo-order", "--format=%H %P", "-n", "\(limit)", "--branches"])
            .split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        let commits = log.map { GraphFixture.commit($0[0], parents: Array($0.dropFirst())) }
        let refs = branches.map { GraphFixture.local($0[0], $0[1], head: $0[0] == head) }
        let headSha = branches.first { $0[0] == head }![1]
        return GraphInput(commits: commits, headSha: headSha, refs: refs)
    }

    @Test("Filmstrip", arguments: [
        ("flow", "develop", "feature/cart"),
        ("flow", "feature/cart", "main"),
        ("copy", "main", "feat/commit-graph-g3-remotes"),
    ])
    func film(repo: String, from: String, to: String) throws {
        let base = ProcessInfo.processInfo.environment["G5_REPOS"] ?? "/tmp"
        let path = base + "/" + (repo == "copy" ? "gitforge-copy" : repo)
        let old = try loadInput(repo: path, head: from)
        let new = try loadInput(repo: path, head: to)
        let oldLayout = CommitGraphEngine.layout(old)
        let layout = CommitGraphEngine.layout(new)
        let motion = GraphMotionBuilder.motion(from: old, to: new, newLayout: layout)
        let rows = min(layout.rows.count, 34)
        let lanes = max(layout.columnCount, oldLayout.columnCount)
        let progresses: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        let style = GraphStyle(metrics: DensityMetrics.regular.graph)
        let pitch: CGFloat = 29
        let width = style.gutterWidth(lanes: lanes)
        let view = HStack(alignment: .top, spacing: 18) {
            column(rows: oldLayout.rows.prefix(rows), shas: old.commits.prefix(rows).map(\.sha), motion: [:],
                   progress: 1, style: style, width: width, pitch: pitch, head: old.headSha, title: "before")
            ForEach(progresses, id: \.self) { progress in
                column(rows: layout.rows.prefix(rows), shas: new.commits.prefix(rows).map(\.sha), motion: motion,
                       progress: UnitCurve.easeInOut.value(at: progress), style: style, width: width, pitch: pitch,
                       head: new.headSha, title: "\(Int(progress * 300)) ms")
            }
        }
        .padding(12)
        .background(Color(white: 0.1))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        try FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: Self.out)
            .appendingPathComponent("\(repo)-\(from)-to-\(to)".replacingOccurrences(of: "/", with: "_") + ".png"))
        G5Log.write("G5FILM \(repo) \(from)->\(to) moving=\(motion.count) rows=\(layout.rows.count)")
    }

    private func column(rows: ArraySlice<GraphRow>, shas: [String], motion: [String: GraphRowMotion],
                        progress: CGFloat, style: GraphStyle, width: CGFloat, pitch: CGFloat,
                        head: String?, title: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white)
            Canvas { context, size in
                let height = GraphRowGeometry.canvasHeight(pitch: pitch, metrics: style.metrics)
                let bleed = GraphRowGeometry.bleed(for: style.metrics)
                for (index, row) in rows.enumerated() {
                    var copy = context
                    copy.translateBy(x: 0, y: CGFloat(index) * pitch - bleed)
                    let lanes = motion[shas[index]].map { GraphRowLanes(style: style, motion: $0, progress: progress) }
                    let painter = GraphRowPainter(style: style, size: CGSize(width: width, height: height),
                                                  rowSpacing: 1, lanes: lanes)
                    painter.drawSteps(of: row, in: &copy)
                    painter.drawNode(row.node, as: GraphNodeStyle.for(row, isHeadCommit: shas[index] == head),
                                     isSelected: false, isHovered: false, in: &copy)
                }
            }
            .frame(width: width, height: CGFloat(rows.count) * pitch)
        }
    }
}

@Suite("G5 scratch dump")
@MainActor
struct G5ScratchDump {
    @Test func dump() throws {
        let base = ProcessInfo.processInfo.environment["G5_REPOS"] ?? "/tmp"
        let film = G5ScratchFilm()
        let env = ProcessInfo.processInfo.environment
        let repo = env["G5_DUMP_REPO"] ?? "flow"
        let old = try film.loadInput(repo: base + "/" + repo, head: env["G5_DUMP_FROM"] ?? "feature/cart")
        let new = try film.loadInput(repo: base + "/" + repo, head: env["G5_DUMP_TO"] ?? "main")
        G5Log.write("DUMP head \(new.headBranch ?? "-") \(new.headSha ?? "-") refs \(new.refs.filter(\.isHead).map(\.name))")
        let oldLayout = CommitGraphEngine.layout(old)
        let layout = CommitGraphEngine.layout(new)
        let motion = GraphMotionBuilder.motion(from: old, to: new, newLayout: layout)
        func steps(_ s: [GraphStep]) -> String { s.map { "\($0.from)>\($0.to)" }.joined(separator: " ") }
        for row in (Int(env["G5_DUMP_FIRST"] ?? "12") ?? 12)..<min(layout.rows.count, Int(env["G5_DUMP_LAST"] ?? "60") ?? 60) {
            let sha = new.commits[row].sha
            let m = motion[sha]
            G5Log.write("DUMP r\(row) old node \(oldLayout.rows[row].node.column) above[\(steps(oldLayout.rows[row].stepsAbove))] below[\(steps(oldLayout.rows[row].stepsBelow))] | new node \(layout.rows[row].node.column) above[\(steps(layout.rows[row].stepsAbove))] below[\(steps(layout.rows[row].stepsBelow))] | m a\(m?.above ?? []) c\(m?.center ?? []) b\(m?.below ?? [])")
        }
    }
}
