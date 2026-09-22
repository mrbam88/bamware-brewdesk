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

/// Locale is the sole argument: `swift scripts/compose_app_store_screenshots.swift [en|es]`
/// (default `en`). `en` composes fastlane/screenshots/raw → en-US; `es`
/// composes fastlane/screenshots/raw-es → es-ES with translated captions.
enum CaptureLocale: String {
    case en
    case es

    var rawDirectoryName: String {
        switch self {
        case .en: "raw"
        case .es: "raw-es"
        }
    }

    var outputDirectoryName: String {
        switch self {
        case .en: "en-US"
        case .es: "es-ES"
        }
    }
}

let localeArgument = CommandLine.arguments.dropFirst().first ?? "en"
guard let captureLocale = CaptureLocale(rawValue: localeArgument) else {
    fatalError("Unknown locale \(localeArgument) — expected en or es")
}

/// Captions per slide, per locale. Spanish mirrors the tone of
/// fastlane/metadata/es-ES (evidencia, portátiles, sin historial de ubicación).
struct Captions {
    let headline: String
    let evidence: String
}

let captions: [String: [CaptureLocale: Captions]] = [
    "01": [
        .en: Captions(
            headline: "See the evidence, not just a rating.",
            evidence: "SOURCE  /  CONFIDENCE  /  OBSERVED"
        ),
        .es: Captions(
            headline: "Ve la evidencia, no solo una nota.",
            evidence: "FUENTE  /  CONFIANZA  /  OBSERVADO"
        ),
    ],
    // Supervisor revision (PR #237): replaces the filter-popover shot with
    // the actual filtered RESULT — confirmed matches vs. an honestly
    // unresolved "might match" bucket — real production data, not a
    // scenario fixture.
    "02": [
        .en: Captions(
            headline: "Filters that admit what they don't know.",
            evidence: "CONFIRMED  /  MIGHT MATCH · UNKNOWN"
        ),
        .es: Captions(
            headline: "Filtros que admiten lo que no saben.",
            evidence: "CONFIRMADO  /  PODRÍA COINCIDIR · DESCONOCIDO"
        ),
    ],
    // Caption intentionally carries no specific venue count (fix #5): this
    // shot is a granted-location neighborhood view, not the full NYC
    // dataset, so a citywide number on screen would be unbacked by what's
    // actually rendered.
    "03": [
        .en: Captions(
            headline: "A Work Fit map for where you work.",
            evidence: "REAL SPOTS NEARBY  /  TRANSPARENT SCORES"
        ),
        .es: Captions(
            headline: "Un mapa Work Fit para donde trabajas.",
            evidence: "LUGARES REALES CERCA  /  PUNTUACIONES TRANSPARENTES"
        ),
    ],
    "04": [
        .en: Captions(
            headline: "Every score shows its work.",
            evidence: "ESTIMATES STAY LABELED"
        ),
        .es: Captions(
            headline: "Cada puntuación muestra su evidencia.",
            evidence: "LAS ESTIMACIONES QUEDAN ETIQUETADAS"
        ),
    ],
    "05": [
        .en: Captions(
            headline: "Search finds real spots, fast.",
            evidence: "TYPE TO SEARCH  /  ALL OF NYC"
        ),
        .es: Captions(
            headline: "La búsqueda encuentra lugares reales, rápido.",
            evidence: "ESCRIBE PARA BUSCAR  /  TODO NYC"
        ),
    ],
    "06": [
        .en: Captions(
            headline: "Pick up where you left off.",
            evidence: "RECENT SEARCHES  /  ONE TAP BACK"
        ),
        .es: Captions(
            headline: "Retoma donde lo dejaste.",
            evidence: "BÚSQUEDAS RECIENTES  /  UN TOQUE PARA VOLVER"
        ),
    ],
    "07": [
        .en: Captions(
            headline: "Haven't checked one yet? We say so.",
            evidence: "NOT RATED YET  /  BEEN HERE? RATE IT."
        ),
        .es: Captions(
            headline: "¿Aún no lo revisamos? Te lo decimos.",
            evidence: "SIN CALIFICAR AÚN  /  ¿ESTUVISTE AQUÍ? CALIFÍCALO."
        ),
    ],
    "08": [
        .en: Captions(
            headline: "Sign in if you want to. Never to browse.",
            evidence: "APPLE  /  GOOGLE  /  EMAIL"
        ),
        .es: Captions(
            headline: "Inicia sesión si quieres. Nunca para explorar.",
            evidence: "APPLE  /  GOOGLE  /  CORREO"
        ),
    ],
    "09": [
        .en: Captions(
            headline: "Save the spots you'll actually return to.",
            evidence: "LOCAL ONLY OR SYNCED  /  YOUR CHOICE"
        ),
        .es: Captions(
            headline: "Guarda los lugares a los que volverás.",
            evidence: "SOLO EN EL DISPOSITIVO O SINCRONIZADO"
        ),
    ],
]

func caption(_ index: String) -> Captions {
    guard let entry = captions[index]?[captureLocale] else {
        fatalError("No \(captureLocale.rawValue) captions for slide \(index)")
    }
    return entry
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
        headline: caption("01").headline,
        evidence: caption("01").evidence,
        background: oat,
        foreground: espresso,
        accent: clay
    ),
    Slide(
        input: "02-honest-filters.png",
        output: "02_honest_filters.png",
        index: "02",
        headline: caption("02").headline,
        evidence: caption("02").evidence,
        background: foam,
        foreground: espresso,
        accent: moss
    ),
    Slide(
        input: "03-work-fit-map.png",
        output: "03_work_fit_across_nyc.png",
        index: "03",
        headline: caption("03").headline,
        evidence: caption("03").evidence,
        background: espresso,
        foreground: foam,
        accent: clay
    ),
    Slide(
        input: "04-honest-by-design.png",
        output: "04_every_score_shows_its_work.png",
        index: "04",
        headline: caption("04").headline,
        evidence: caption("04").evidence,
        background: oat,
        foreground: espresso,
        accent: clay
    ),
    Slide(
        input: "05-search-results.png",
        output: "05_search_the_city.png",
        index: "05",
        headline: caption("05").headline,
        evidence: caption("05").evidence,
        background: foam,
        foreground: espresso,
        accent: moss
    ),
    Slide(
        input: "06-recent-searches.png",
        output: "06_recent_searches.png",
        index: "06",
        headline: caption("06").headline,
        evidence: caption("06").evidence,
        background: oat,
        foreground: espresso,
        accent: clay
    ),
    Slide(
        input: "07-not-rated-yet.png",
        output: "07_not_rated_yet.png",
        index: "07",
        headline: caption("07").headline,
        evidence: caption("07").evidence,
        background: espresso,
        foreground: foam,
        accent: clay
    ),
    Slide(
        input: "08-sign-in.png",
        output: "08_sign_in_optional.png",
        index: "08",
        headline: caption("08").headline,
        evidence: caption("08").evidence,
        background: espresso,
        foreground: foam,
        accent: moss
    ),
    Slide(
        input: "09-saved-spot.png",
        output: "09_save_your_spots.png",
        index: "09",
        headline: caption("09").headline,
        evidence: caption("09").evidence,
        background: oat,
        foreground: espresso,
        accent: clay
    ),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let rawDirectory = root.appendingPathComponent("fastlane/screenshots/\(captureLocale.rawDirectoryName)")
let outputDirectory = root.appendingPathComponent("fastlane/screenshots/\(captureLocale.outputDirectoryName)")

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
