import Foundation

// Report content (brewdesk#48, Apple 1.2: "a mechanism to report offensive
// content"). Scope guard: the venue engine has NO reports endpoint today and
// this ticket does not add one — reports flow through a protocol seam with a
// local spool implementation, so the UI, tests, and review walkthrough are
// real while the wire lands in its own venue-engine ticket.
//
// PROPOSED ENGINE CONTRACT (for the follow-up venue-engine ticket):
//   POST /v1/reports
//   body: { venueId?: string, photoUrl: string, contributorName?: string,
//           reason: "inappropriate" | "spam" | "not_venue" | "other",
//           submittedBy: string }   // per-install UUID or account userId
//   → 201 { ok: true }; zod .strict() like the observations route.
// When that ships, `EngineReportService: ContentReporting` posts the spool
// (plus new reports) there; nothing above this seam changes.

/// Why a photo is being reported. Raw values are the proposed wire values.
public enum ReportReason: String, CaseIterable, Codable, Sendable {
    case inappropriate
    case spam
    /// The photo is not of this venue.
    case notThisVenue = "not_venue"
    case other

    /// User-facing label for the report sheet.
    public var label: String {
        switch self {
        case .inappropriate: "Inappropriate or offensive"
        case .spam: "Spam or misleading"
        case .notThisVenue: "Not a photo of this venue"
        case .other: "Something else"
        }
    }
}

/// One flagged piece of community content. `photoURL` is the stable id the
/// engine can resolve a photo by (`VenuePhoto.id` is its URL).
public struct ContentReport: Codable, Equatable, Sendable {
    public let venueName: String
    public let photoURL: String
    public let contributorName: String?
    public let reason: ReportReason
    public let reportedAt: Date

    public init(
        venueName: String,
        photoURL: String,
        contributorName: String?,
        reason: ReportReason,
        reportedAt: Date = Date()
    ) {
        self.venueName = venueName
        self.photoURL = photoURL
        self.contributorName = contributorName
        self.reason = reason
        self.reportedAt = reportedAt
    }
}

/// Seam for report submission. UI and tests depend on this, not on any
/// concrete transport (see the proposed engine contract above).
public protocol ContentReporting: Sendable {
    func submitReport(_ report: ContentReport) async throws
}

/// v1 implementation: persists reports locally so none are lost, to be
/// drained to the engine endpoint when it exists. Reports are also actionable
/// today without it — the content-rules screen publishes the contact address
/// (Apple 1.2's published-contact requirement) and objectionable content is
/// acted on within 24 hours.
public final class ReportSpool: ContentReporting, @unchecked Sendable {
    public static let defaultsKey = "brewdesk.pending-reports"

    /// UserDefaults is documented thread-safe; not Sendable-annotated —
    /// hence `@unchecked` (same as `ContributorBlockStore`).
    private let defaults: UserDefaults

    /// Injectable defaults keep package tests off `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func submitReport(_ report: ContentReport) async throws {
        var pending = Self.pendingReports(defaults: defaults)
        pending.append(report)
        let data = try JSONEncoder().encode(pending)
        defaults.set(data, forKey: Self.defaultsKey)
    }

    public static func pendingReports(defaults: UserDefaults = .standard) -> [ContentReport] {
        guard let data = defaults.data(forKey: defaultsKey),
              let reports = try? JSONDecoder().decode([ContentReport].self, from: data)
        else { return [] }
        return reports
    }
}
