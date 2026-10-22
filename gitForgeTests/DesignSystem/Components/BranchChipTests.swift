import CoreGraphics
import SwiftUI
import Testing
@testable import gitForge

/// The ahead / behind counters and the dashed border of `BranchChip` (graph v3 spec §4.4).
@Suite("BranchChip")
@MainActor
struct BranchChipTests {

    @Test("Counter text", arguments: [(0, 0, nil), (2, 0, "↑2"), (0, 3, "↓3"), (1, 2, "↑1 ↓2")] as [(Int, Int, String?)])
    func counterText(ahead: Int, behind: Int, expected: String?) {
        #expect(BranchChip.counterText(ahead: ahead, behind: behind) == expected)
    }

    @Test("A chip is spoken with its counts, ahead first; with none it adds nothing")
    func spokenCounters() {
        #expect(BranchChip.spokenCounters(ahead: 0, behind: 0) == nil)
        #expect(BranchChip.spokenCounters(ahead: 2, behind: 0) == String(localized: "\(2) ahead"))
        #expect(BranchChip.spokenCounters(ahead: 0, behind: 3) == String(localized: "\(3) behind"))
        #expect(BranchChip.spokenCounters(ahead: 2, behind: 3)
                == "\(String(localized: "\(2) ahead")), \(String(localized: "\(3) behind"))")
    }

    // MARK: Rendering

    /// A pure red lane colour, whatever the appearance: the system's reds change with it.
    private static let lane = Color(red: 1, green: 0, blue: 0)

    /// `chip` over black at 2 pixels per point, at its own size; nil, with an issue recorded, when
    /// the renderer gives no image.
    private static func render(_ chip: BranchChip, sourceLocation: SourceLocation = #_sourceLocation) -> Bitmap? {
        let renderer = ImageRenderer(content: chip.appTheme(AppTheme()).background(Color.black))
        renderer.scale = 2
        guard let image = renderer.cgImage, let bitmap = Bitmap(image) else {
            Issue.record("No image rendered", sourceLocation: sourceLocation)
            return nil
        }
        return bitmap
    }

    private static func remoteChip(dashed: Bool) -> BranchChip {
        BranchChip(name: "feature/x", remote: true, laneColor: lane, dashedBorder: dashed)
    }

    /// The pixels of pixel row `y` along the top border, between the rounded corners.
    private static func topBorder(of bitmap: Bitmap, row y: Int) -> [Pixel] {
        let corner = Int((Radius.chip + 1) * bitmap.scale)
        return (corner..<(bitmap.width - corner)).map { bitmap.pixel(x: $0, y: y) }
    }

    /// The red of the border (60 % of the lane colour over black, or all of it with Increase
    /// Contrast).
    private static func isBorder(_ pixel: Pixel) -> Bool { pixel.red > 100 && pixel.green < 40 && pixel.blue < 40 }

    private static func isBlack(_ pixel: Pixel) -> Bool { pixel.red < 20 && pixel.green < 20 && pixel.blue < 20 }

    @Test("A dashed chip leaves gaps along its top border; a solid one doesn't")
    func dashedBorder() throws {
        let dashed = try #require(Self.render(Self.remoteChip(dashed: true)))
        let solid = try #require(Self.render(Self.remoteChip(dashed: false)))
        // The border is 1 pt, two pixel rows, and it is drawn inside the chip: both rows have it.
        for row in 0...1 {
            let dashedTop = Self.topBorder(of: dashed, row: row)
            #expect(dashedTop.contains(where: Self.isBorder), "row \(row)")
            #expect(dashedTop.contains(where: Self.isBlack), "row \(row)")
            let solidTop = Self.topBorder(of: solid, row: row)
            #expect(solidTop.allSatisfy(Self.isBorder), "row \(row)")
            #expect(!solidTop.contains(where: Self.isBlack), "row \(row)")
        }
    }

    @Test("Counters widen the chip; a chip with none is as wide as before")
    func countersWiden() throws {
        let plain = try #require(Self.render(BranchChip(name: "main", laneColor: Self.lane)))
        let zero = try #require(Self.render(BranchChip(name: "main", laneColor: Self.lane, ahead: 0, behind: 0)))
        let ahead = try #require(Self.render(BranchChip(name: "main", laneColor: Self.lane, ahead: 2)))
        let both = try #require(Self.render(BranchChip(name: "main", laneColor: Self.lane, ahead: 2, behind: 3)))
        #expect(zero.width == plain.width)
        #expect(ahead.width > plain.width)
        #expect(both.width > ahead.width)
    }
}

// MARK: - Reading pixels

/// One 8-bit RGBA pixel, premultiplied.
private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

/// A rendered image read back as 8-bit sRGB RGBA, its top row first.
private struct Bitmap {
    /// Pixels per point of the renderer's `scale`.
    let scale: CGFloat = 2
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Draws `image` into a bitmap of known layout, so its bytes read the same whatever format the
    /// renderer chose. Nil if the bitmap can't be made.
    init?(_ image: CGImage) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let index = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        return Pixel(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
    }
}
