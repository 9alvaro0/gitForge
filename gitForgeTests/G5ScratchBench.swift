import Foundation
import SwiftUI
import Testing
@testable import gitForge

// SCRATCH: G5 cost measurement. Never merged.
@Suite("G5 scratch bench", .serialized)
struct G5ScratchBench {
    private func median(_ body: () -> Void) -> Duration {
        (0..<5).map { _ in ContinuousClock().measure(body) }.sorted()[2]
    }

    private func inputs(count: Int, loaded: Int?) -> (main: GraphInput, feature: GraphInput, featureName: String) {
        let (all, allRefs) = GraphFixture.synthetic(commits: count, branches: 12, seed: 7)
        let commits = loaded.map { Array(all.prefix($0)) } ?? all
        let shas = Set(commits.map(\.sha))
        let refs = allRefs.filter { shas.contains($0.targetSha) }
        let rowOf = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($1.sha, $0) })
        // The feature whose tip is lowest in the first 200 rows: the longest slide.
        let feature = refs.dropFirst().filter { rowOf[$0.targetSha]! < 200 }
            .max { rowOf[$0.targetSha]! < rowOf[$1.targetSha]! }!
        let main = GraphInput(commits: commits, headSha: refs[0].targetSha, refs: refs)
        let featureRefs = refs.map { ref in
            GraphFixture.local(ref.name, ref.targetSha, head: ref.name == feature.name)
        }
        let other = GraphInput(commits: commits, headSha: feature.targetSha, refs: featureRefs)
        return (main, other, feature.name)
    }

    @Test("Motion cost against the layout pass", arguments: [(50_000, Int?.none), (50_000, Int?.some(200)),
                                                            (50_000, Int?.some(2_000))])
    func motionCost(count: Int, loaded: Int?) {
        let (main, feature, name) = inputs(count: count, loaded: loaded)
        let layout = CommitGraphEngine.layout(feature)
        let layoutTime = median { _ = CommitGraphEngine.layout(feature) }
        var rows = 0
        let motionTime = median { rows = GraphMotionBuilder.motion(from: main, to: feature, newLayout: layout).count }
        G5Log.write("G5BENCH motion rows=\(feature.commits.count) to=\(name) layout=\(layoutTime) motion=\(motionTime) moving=\(rows)")
    }

    @Test("Row drawing cost with and without the slide")
    @MainActor
    func drawCost() {
        let (main, feature, _) = inputs(count: 50_000, loaded: 200)
        let layout = CommitGraphEngine.layout(feature)
        let motion = GraphMotionBuilder.motion(from: main, to: feature, newLayout: layout)
        let rows = Array(layout.rows.prefix(40))
        let shas = feature.commits.prefix(40).map(\.sha)
        let style = GraphStyle()
        let width = style.gutterWidth(lanes: layout.columnCount)
        let height = GraphRowGeometry.canvasHeight(pitch: 29, metrics: style.metrics)
        let moving = shas.filter { motion[$0] != nil }.count

        func render(frames: Int, animated: Bool) -> Duration {
            let view = Canvas { context, size in
                for frame in 0..<frames {
                    let progress = CGFloat(frame) / CGFloat(max(frames - 1, 1))
                    for (index, row) in rows.enumerated() {
                        var copy = context
                        copy.translateBy(x: 0, y: CGFloat(index) * 29)
                        let lanes = animated ? motion[shas[index]].map {
                            GraphRowLanes(style: style, motion: $0, progress: progress)
                        } : nil
                        let painter = GraphRowPainter(style: style, size: CGSize(width: width, height: height),
                                                      rowSpacing: 1, lanes: lanes)
                        painter.drawSteps(of: row, in: &copy)
                        painter.drawNode(row.node, as: .commit, isSelected: false, isHovered: false, in: &copy)
                    }
                }
            }
            .frame(width: width, height: CGFloat(rows.count) * 29)
            return median {
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                _ = renderer.cgImage
            }
        }
        let still = render(frames: 36, animated: false)
        let sliding = render(frames: 36, animated: true)
        G5Log.write("G5BENCH draw rows=40 moving=\(moving) frames=36 still=\(still) sliding=\(sliding)")
    }
}

enum G5Log {
    static func write(_ line: String) {
        let path = ProcessInfo.processInfo.environment["G5_BENCH_LOG"] ?? "/tmp/g5bench.log"
        let data = Data((line + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
