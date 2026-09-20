import BrewDeskKit
import SwiftUI
import Testing
@testable import BrewDesk

/// Automated guard for the exact bug bamware-brewdesk#205 was filed over:
/// the cup body must never dim, fade, or change at all before the
/// hand-off fade begins. A manual contact-sheet review (see the PR) is a
/// one-time human check; this renders the actual production
/// `BrewDeskMark` view — not a stand-in — via `ImageRenderer` at the
/// ticket's own sample points and inspects real pixels in the cup body,
/// so the same guarantee is checked mechanically on every future run.
@MainActor
@Suite struct LaunchRevealPixelGuardTests {
    /// The cup body's own geometry, mirrored from `BrewDeskMarkGeometry`
    /// (internal to `BrewDeskKit`, so not reachable from here): canvas
    /// 360×436, cup spans y 255...399, horizontal center x 174. This test
    /// samples the midpoint of that span — comfortably inside the cup on
    /// every launch-reveal frame, never near an edge/antialiasing pixel.
    private static let cupSampleX = 174.0 / 360.0
    private static let cupSampleY = (255.0 + 399.0) / 2 / 436.0

    private static let markSize = CGSize(width: 120, height: 145)

    /// The ticket's own sample points — every 150ms from 0 through 700ms.
    /// All are comfortably before `LaunchRevealTimeline.crossfadeStart`
    /// (760ms), which the test below also asserts directly rather than
    /// assuming.
    private static let sampleMS: [Double] = [0, 150, 300, 450, 600, 700]

    @Test func cupBodyStaysPureWhiteAtEverySampleBeforeHandoff() throws {
        for ms in Self.sampleMS {
            #expect(ms < LaunchRevealTimeline.crossfadeStart, "\(ms)ms guard sample must be before hand-off")
            let stage = LaunchRevealTimeline.frame(atElapsedMS: ms)
            let pixel = try #require(Self.renderAndSampleCupPixel(stage: stage), "failed to render/sample the mark at \(ms)ms")
            #expect(pixel.alpha > 0.98, "cup body is not fully opaque at \(ms)ms (alpha \(pixel.alpha)) — it dimmed or vanished")
            #expect(
                pixel.red > 0.98 && pixel.green > 0.98 && pixel.blue > 0.98,
                "cup body is not pure white at \(ms)ms (r\(pixel.red) g\(pixel.green) b\(pixel.blue)) — something is tinting/shading it"
            )
        }
    }

    private struct SampledPixel {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private static func renderAndSampleCupPixel(stage: BrewDeskMarkStage) -> SampledPixel? {
        let view = BrewDeskMark(tint: .white, mode: .stage(stage), isAnimated: true)
            .frame(width: markSize.width, height: markSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        let x = Int(CGFloat(cgImage.width) * cupSampleX)
        let y = Int(CGFloat(cgImage.height) * cupSampleY)
        return samplePixel(in: cgImage, x: x, y: y)
    }

    /// Reads one pixel directly out of `image`'s own backing store — no
    /// re-draw into a second context, which sidesteps any question about
    /// which way a fresh `CGContext`'s coordinate space points. Row 0 is
    /// the image's own top row, exactly as `ImageRenderer` produced it.
    /// Requires 8-bit RGBA (`ImageRenderer`'s own default); anything else
    /// is treated as unreadable rather than silently misread.
    private static func samplePixel(in image: CGImage, x: Int, y: Int) -> SampledPixel? {
        let width = image.width
        let height = image.height
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let provider = image.dataProvider, let data = provider.data,
              let bytes = CFDataGetBytePtr(data)
        else { return nil }

        let bytesPerRow = image.bytesPerRow
        let offset = y * bytesPerRow + x * 4
        guard offset + 3 < CFDataGetLength(data) else { return nil }

        let alphaInfo = image.alphaInfo
        let byteOrderIsRGBA = alphaInfo == .premultipliedLast || alphaInfo == .last || alphaInfo == .noneSkipLast
        let (rIdx, gIdx, bIdx, aIdx) = byteOrderIsRGBA ? (0, 1, 2, 3) : (1, 2, 3, 0)
        let isPremultiplied = alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst
        let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipLast && alphaInfo != .noneSkipFirst

        let alpha = hasAlpha ? Double(bytes[offset + aIdx]) / 255 : 1
        guard alpha > 0 else { return SampledPixel(red: 0, green: 0, blue: 0, alpha: 0) }
        let rawRed = Double(bytes[offset + rIdx]) / 255
        let rawGreen = Double(bytes[offset + gIdx]) / 255
        let rawBlue = Double(bytes[offset + bIdx]) / 255
        let divisor = isPremultiplied ? alpha : 1
        let red = min(rawRed / divisor, 1)
        let green = min(rawGreen / divisor, 1)
        let blue = min(rawBlue / divisor, 1)
        return SampledPixel(red: red, green: green, blue: blue, alpha: alpha)
    }
}
