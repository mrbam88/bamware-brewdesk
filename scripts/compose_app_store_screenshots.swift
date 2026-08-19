import AppKit

struct Slide {
    let input: String
    let output: String
    let index: String
    let headline: String
    let evidence: String
    let background: NSColor
    let foreground: NSColor
    let accent: NSColor
}

let width = 1320
let height = 2868
let screenshotWidth: CGFloat = 1068
let screenshotHeight: CGFloat = 2320
let screenshotTop: CGFloat = 516

let espresso = NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.08, alpha: 1)
let oat = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1)
let foam = NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.94, alpha: 1)
let moss = NSColor(calibratedRed: 0.24, green: 0.38, blue: 0.27, alpha: 1)
let clay = NSColor(calibratedRed: 0.73, green: 0.35, blue: 0.20, alpha: 1)

let slides = [
    Slide(
        input: "01-claim-provenance.png",
        output: "01_evidence_not_ratings.png",
        index: "01",
        headline: "See the evidence, not just a rating.",
        evidence: "SOURCE  /  CONFIDENCE  /  OBSERVED",
        background: oat,
        foreground: espresso,
        accent: clay
    ),
    Slide(
        input: "02-work-filters.png",
        output: "02_filters_for_work.png",
        index: "02",
        headline: "Filter for the way you actually work.",
        evidence: "LAPTOPS  /  WI-FI  /  OUTLETS",
        background: foam,
        foreground: espresso,
        accent: moss
    ),
    Slide(
        input: "03-work-fit-map.png",
        output: "03_work_fit_across_nyc.png",
        index: "03",
        headline: "A Work Fit map built for NYC.",
        evidence: "2,000+ CAFES  /  TRANSPARENT SCORES",
        background: espresso,
        foreground: foam,
        accent: clay
    ),
    Slide(
        input: "04-honest-by-design.png",
        output: "04_every_score_shows_its_work.png",
        index: "04",
        headline: "Every score shows its work.",
        evidence: "ESTIMATES STAY LABELED",
        background: oat,
        foreground: espresso,
        accent: clay
    ),
    Slide(
        input: "05-location-is-optional.png",
        output: "05_location_is_optional.png",
        index: "05",
        headline: "Location is useful. Never required.",
        evidence: "YOUR CHOICE  /  NO LOCATION HISTORY",
        background: foam,
        foreground: espresso,
        accent: moss
    ),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let rawDirectory = root.appendingPathComponent("fastlane/screenshots/raw")
let outputDirectory = root.appendingPathComponent("fastlane/screenshots/en-US")

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func font(named names: [String], size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    for name in names {
        if let font = NSFont(name: name, size: size) { return font }
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(
    _ text: String,
    x: CGFloat,
    top: CGFloat,
    maxWidth: CGFloat,
    font: NSFont,
    color: NSColor,
    tracking: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 2
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph,
        ]
    )
    let bounds = attributed.boundingRect(
        with: NSSize(width: maxWidth, height: 400),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let rect = NSRect(
        x: x,
        y: CGFloat(height) - top - ceil(bounds.height),
        width: maxWidth,
        height: ceil(bounds.height) + 4
    )
    attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

for slide in slides {
    guard let bitmapContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Unable to create screenshot canvas")
    }
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    slide.background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    drawText(
        "BREWDESK  /  \(slide.index)",
        x: 90,
        top: 68,
        maxWidth: 1104,
        font: font(named: ["SFMono-Semibold", "Menlo-Bold"], size: 27, weight: .semibold),
        color: slide.accent,
        tracking: 3.2
    )
    drawText(
        slide.headline,
        x: 88,
        top: 126,
        maxWidth: 1108,
        font: font(named: ["NewYork-Semibold", "New York"], size: 76, weight: .bold),
        color: slide.foreground
    )

    let evidenceRect = NSRect(x: 88, y: CGFloat(height) - 448, width: 1108, height: 58)
    let evidencePath = NSBezierPath(roundedRect: evidenceRect, xRadius: 16, yRadius: 16)
    slide.accent.withAlphaComponent(0.16).setFill()
    evidencePath.fill()
    drawText(
        slide.evidence,
        x: 112,
        top: 408,
        maxWidth: 1060,
        font: font(named: ["SFMono-Semibold", "Menlo-Bold"], size: 24, weight: .semibold),
        color: slide.foreground.withAlphaComponent(0.78),
        tracking: 1.4
    )

    let imageURL = rawDirectory.appendingPathComponent(slide.input)
    guard let image = NSImage(contentsOf: imageURL) else {
        fatalError("Unable to load \(imageURL.path)")
    }

    let imageRect = NSRect(
        x: (CGFloat(width) - screenshotWidth) / 2,
        y: CGFloat(height) - screenshotTop - screenshotHeight,
        width: screenshotWidth,
        height: screenshotHeight
    )
    let framePath = NSBezierPath(roundedRect: imageRect, xRadius: 64, yRadius: 64)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    framePath.fill()
    NSShadow().set()

    NSGraphicsContext.saveGraphicsState()
    framePath.addClip()
    image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    slide.foreground.withAlphaComponent(0.10).setStroke()
    framePath.lineWidth = 2
    framePath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let image = bitmapContext.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(slide.output)")
    }
    try png.write(to: outputDirectory.appendingPathComponent(slide.output))
    print("wrote \(slide.output)")
}
