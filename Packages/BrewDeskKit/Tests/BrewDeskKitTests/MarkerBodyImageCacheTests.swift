import SwiftUI
import Testing
import UIKit
@testable import BrewDeskKit

/// bd#227 (TestFlight build 29 — "weird box... really small" around every
/// pin; "in dark mode... it's not bright enough, it's hard to see"):
/// regression coverage for `MapAnnotationViews.MarkerBodyImageCache`'s
/// padded raster and explicit-appearance rendering.
struct MarkerBodyImageCacheTests {
    /// Reads the RGBA bytes at one pixel of a `UIImage`, in the image's own
    /// pixel space (not points) — `nil` means the image couldn't be decoded
    /// into a bitmap context at all (test setup failure, not a meaningful
    /// zero).
    private func pixel(_ image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return nil }
        var pixelData = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: -x, y: -(cgImage.height - 1 - y), width: cgImage.width, height: cgImage.height))
        return (pixelData[0], pixelData[1], pixelData[2], pixelData[3])
    }

    /// Regression for the "weird box" defect: every corner of the padded
    /// raster must be fully transparent, at every real numbered-tier size
    /// stop, both appearances.
    @Test func cachedRasterCornersAreFullyTransparent() {
        let diameters: [CGFloat] = [14, 15, 20, 23, MapAnnotationPlanner.selectedDiameter]
        for diameter in diameters {
            for isDark in [true, false] {
                let image = MarkerBodyImageCache.image(score: 75, diameter: diameter, isDark: isDark)
                guard let cgImage = image.cgImage else {
                    Issue.record("no cgImage for diameter \(diameter) isDark \(isDark)")
                    continue
                }
                let corners = [
                    (0, 0), (cgImage.width - 1, 0),
                    (0, cgImage.height - 1), (cgImage.width - 1, cgImage.height - 1),
                ]
                for (x, y) in corners {
                    let sample = pixel(image, x: x, y: y)
                    #expect(sample?.a == 0, "diameter \(diameter) isDark \(isDark) corner (\(x),\(y)) alpha \(String(describing: sample?.a)) — expected fully transparent, not a raster box edge")
                }
            }
        }
    }

    /// The padded canvas must actually be LARGER than the raw pin slot on
    /// every side by at least `bodyRasterPadding` — a regression guard
    /// against someone "fixing" the box by shrinking the drawn shape
    /// instead of padding the canvas (which would violate "keep sizes").
    @Test func cachedRasterCanvasIsPaddedBeyondTheLogicalPinSlot() {
        let diameter: CGFloat = 20
        let frameHeight = diameter * MapAnnotationPlanner.tailHeightFactor
        let image = MarkerBodyImageCache.image(score: 75, diameter: diameter, isDark: true)
        guard let cgImage = image.cgImage else {
            Issue.record("no cgImage")
            return
        }
        let scale = image.scale
        let widthPoints = CGFloat(cgImage.width) / scale
        let heightPoints = CGFloat(cgImage.height) / scale
        #expect(widthPoints >= diameter + 2 * MarkerBodyImageCache.bodyRasterPadding - 0.5)
        #expect(heightPoints >= frameHeight + 2 * MarkerBodyImageCache.bodyRasterPadding - 0.5)
    }

    /// Regression for "dark mode too dim": the cached raster's HEAD CENTRE
    /// pixel — where the vertical gradient is essentially the plain tier
    /// fill (52% stop) — must read close to `BrewDeskPalette`'s dark-map
    /// ramp value, not the light-map ramp.
    @Test func darkMapRasterHeadCentreMatchesTheDarkRampNotTheLightRamp() {
        let diameter: CGFloat = 23
        let score = 85 // top tier
        let image = MarkerBodyImageCache.image(score: score, diameter: diameter, isDark: true)
        guard let cgImage = image.cgImage else {
            Issue.record("no cgImage")
            return
        }
        let scale = image.scale
        let centreXPoints = MarkerBodyImageCache.bodyRasterPadding + diameter / 2
        let centreYPoints = MarkerBodyImageCache.bodyRasterPadding + diameter / 2
        guard let sample = pixel(image, x: Int(centreXPoints * scale), y: Int(centreYPoints * scale)) else {
            Issue.record("could not sample head centre pixel (canvas \(cgImage.width)x\(cgImage.height))")
            return
        }
        let expectedDark = UIColor(BrewDeskPalette.markerFill(score: score)).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let expectedLight = UIColor(BrewDeskPalette.markerFill(score: score)).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        expectedDark.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        expectedLight.getRed(&lr, green: &lg, blue: &lb, alpha: &la)

        let distToDark = abs(Double(sample.r) - Double(er) * 255) + abs(Double(sample.g) - Double(eg) * 255) + abs(Double(sample.b) - Double(eb) * 255)
        let distToLight = abs(Double(sample.r) - Double(lr) * 255) + abs(Double(sample.g) - Double(lg) * 255) + abs(Double(sample.b) - Double(lb) * 255)
        #expect(distToDark < distToLight, "isDark:true raster's head-centre pixel \(sample) is closer to the LIGHT ramp \((lr, lg, lb)) than the dark ramp \((er, eg, eb))")
        // Bright dark-map ramp: green channel should read solidly bright
        // (>150/255) at the top tier, never a muted/dim value.
        #expect(sample.g > 150, "dark-map top-tier head centre green channel \(sample.g) reads dim, not bright")
    }

    /// Companion sanity check in the OTHER direction — a light-map render
    /// must land near the light ramp, not the dark one.
    @Test func lightMapRasterHeadCentreMatchesTheLightRampNotTheDarkRamp() {
        let diameter: CGFloat = 23
        let score = 85
        let image = MarkerBodyImageCache.image(score: score, diameter: diameter, isDark: false)
        guard let cgImage = image.cgImage else {
            Issue.record("no cgImage")
            return
        }
        let scale = image.scale
        let centreXPoints = MarkerBodyImageCache.bodyRasterPadding + diameter / 2
        let centreYPoints = MarkerBodyImageCache.bodyRasterPadding + diameter / 2
        guard let sample = pixel(image, x: Int(centreXPoints * scale), y: Int(centreYPoints * scale)) else {
            Issue.record("could not sample head centre pixel")
            return
        }
        // Light-map top tier (`#1C5243`) is a dark, desaturated green — the
        // green channel should read notably DIMMER than the bright
        // dark-map equivalent above.
        #expect(sample.g < 140, "light-map top-tier head centre green channel \(sample.g) reads too bright for the dark #1C5243 ramp")
    }

    /// bd#265: the unrated cup pin comes out of the SAME raster cache — a
    /// padded, transparent-cornered image whose head is a neutral grey with
    /// a white cup in it, never a tier color, in both appearances.
    @Test func unratedPinRasterIsNeutralWithAWhiteGlyphAndTransparentCorners() throws {
        for isDark in [true, false] {
            for diameter: CGFloat in [11, 12, 18.5, MapAnnotationPlanner.selectedDiameter] {
                let image = MarkerBodyImageCache.image(score: 0, diameter: diameter, isDark: isDark, isUnrated: true)
                let cgImage = try #require(image.cgImage)
                #expect(pixel(image, x: 0, y: 0)?.a == 0)
                #expect(pixel(image, x: cgImage.width - 1, y: cgImage.height - 1)?.a == 0)
                let scale = image.scale
                let padding = MarkerBodyImageCache.bodyRasterPadding
                // Scan the head: grey body pixels (low chroma) and at least
                // some near-white glyph pixels, nothing saturated.
                var whiteCount = 0
                var greyCount = 0
                let minX = Int(padding * scale), maxX = Int((padding + diameter) * scale)
                let minY = Int(padding * scale), maxY = Int((padding + diameter) * scale)
                for y in stride(from: minY, to: maxY, by: 1) {
                    for x in stride(from: minX, to: maxX, by: 1) {
                        guard let p = pixel(image, x: x, y: y), p.a == 255 else { continue }
                        let chroma = Int(max(p.r, p.g, p.b)) - Int(min(p.r, p.g, p.b))
                        #expect(chroma < 40, "unrated raster has a saturated pixel \(p) at (\(x),\(y))")
                        if p.r > 235, p.g > 235, p.b > 235 { whiteCount += 1 } else { greyCount += 1 }
                    }
                }
                #expect(greyCount > whiteCount, "the head should be mostly neutral body")
                #expect(whiteCount > 0, "no white cup glyph drawn at diameter \(diameter) isDark \(isDark)")
            }
        }
    }

    @Test func unratedAndRatedRastersAreDistinctCacheEntries() {
        let rated = MarkerBodyImageCache.image(score: 0, diameter: 12, isDark: false)
        let unrated = MarkerBodyImageCache.image(score: 0, diameter: 12, isDark: false, isUnrated: true)
        #expect(rated !== unrated)
        #expect(unrated === MarkerBodyImageCache.image(score: 95, diameter: 12, isDark: false, isUnrated: true),
                "an unrated pin's raster must not depend on its fallback score")
    }
}
