// Community capture — submission seam (brewdesk#46) and the real uploader
// (brewdesk#71). This entire file compiles ONLY into Debug builds — the App
// Store binary contains none of it (Guideline 2.3.1, same policy as
// DebugEnvironmentStore). `LiveCaptureSubmissionService` drives the VenueKit
// rail: signed-in check → presign → S3 PUT → confirm → venue-engine intake.
#if DEBUG
import Foundation
import VenueKit

/// The three shots the guided flow asks for, in order (wide → medium → detail).
/// Copy lives here so the spec (docs/community-capture-ux.md), the screens,
/// and the tests all read from one source.
public nonisolated enum CaptureShotKind: String, CaseIterable, Identifiable, Sendable {
    case roomFromDoor = "room-from-door"
    case seatingArea = "seating-area"
    case outlets = "outlets"

    public var id: String { rawValue }

    /// The ask, as shown to the contributor.
    public var title: String {
        switch self {
        case .roomFromDoor: "The room from the door"
        case .seatingArea: "The seating area"
        case .outlets: "The outlets"
        }
    }

    /// One-line "why" shown beneath the ask — people shoot better photos when
    /// they know what the photo is evidence for.
    public var why: String {
        switch self {
        case .roomFromDoor:
            "One wide shot from the entrance shows people what they're walking into."
        case .seatingArea:
            "Tables and chairs — where would you actually work?"
        case .outlets:
            "A wall or floor outlet near seating. No outlets in sight? Skip — that's useful too."
        }
    }

    public var systemImage: String {
        switch self {
        case .roomFromDoor: "door.left.hand.open"
        case .seatingArea: "chair"
        case .outlets: "powerplug"
        }
    }
}

/// What the flow hands the submission seam. A skipped shot is carried
/// honestly as `imageData == nil`, never silently dropped — "no visible
/// outlets" is itself a data point.
public nonisolated struct CaptureSubmission: Equatable, Sendable {
    public nonisolated struct Shot: Equatable, Sendable {
        public let kind: CaptureShotKind
        /// JPEG bytes, or nil when the contributor skipped the shot.
        public let imageData: Data?

        public init(kind: CaptureShotKind, imageData: Data?) {
            self.kind = kind
            self.imageData = imageData
        }
    }

    public let venueID: String
    public let shots: [Shot]

    public init(venueID: String, shots: [Shot]) {
        self.venueID = venueID
        self.shots = shots
    }
}

/// The submission seam. Live: `LiveCaptureSubmissionService` (the real
/// rail). Deterministic (UI tests / previews): `MockCaptureSubmissionService`.
/// Default MainActor isolation — it is called from UI; the networked
/// implementation hops off-main inside URLSession.
public protocol CaptureSubmissionService: AnyObject {
    func submit(_ submission: CaptureSubmission) async throws
}

/// The real uploader (brewdesk#71): requires a signed-in account
/// (brewdesk#48 — the rail is JWT-authenticated), then walks every
/// non-skipped shot through the VenueKit chain in order:
/// presign → S3 PUT → confirm → venue-engine intake link.
///
/// Skipped slots never reach the rail — dating-service PR #19's contract is
/// per-object; "skipped, honestly" is flow state, not an upload. The
/// contributor byline travels to intake so approved photos render it
/// (brewdesk#49).
public final class LiveCaptureSubmissionService: CaptureSubmissionService {
    private let sessionStore: AccountSessionStore
    private let chain: CaptureUploadChain

    public init(
        sessionStore: AccountSessionStore = .shared,
        chain: CaptureUploadChain = CaptureUploadChain(
            rail: UploadRailAPI(),
            storage: S3ObjectUploader(),
            intake: VenueIntakeAPI()
        )
    ) {
        self.sessionStore = sessionStore
        self.chain = chain
    }

    public func submit(_ submission: CaptureSubmission) async throws {
        guard let session = sessionStore.session else {
            throw UploadRailError.signInRequired
        }
        let shots = submission.shots.compactMap { shot in
            shot.imageData.map { CaptureUploadShot(kind: shot.kind.rawValue, jpegData: $0) }
        }
        try await chain.submit(
            venueID: submission.venueID,
            shots: shots,
            contributorName: session.user.name,
            submittedBy: session.user.userId,
            accessToken: session.accessToken
        )
    }
}

/// Launch-time service resolution, same screen-side pattern as
/// `ObservationServiceResolver` / `AccountServiceResolver` so wiring the
/// live rail stays additive to the composition root (VenueDetailScreen
/// still constructs the prototype mock; brewdesk#46).
///
/// - Normal launch: the live rail.
/// - `-UITestScenario` launch: the injected deterministic mock — or, when
///   `-UITestCaptureFailures <n>` is present, a mock scripted to fail the
///   first n submits (pins the upload-failed → retry path in UI tests).
public enum CaptureSubmissionServiceResolver {
    public static func resolve(
        environment: LaunchEnvironment = .current,
        fallback: any CaptureSubmissionService
    ) -> any CaptureSubmissionService {
        guard environment.scenario != nil else {
            return LiveCaptureSubmissionService()
        }
        if let failures = environment.captureFailures {
            return MockCaptureSubmissionService(failuresRemaining: failures)
        }
        return fallback
    }
}

/// In-process stand-in: configurable latency and scripted failures so the
/// confirm screen's submitting/error/retry states are drivable in the
/// simulator and in tests. Records what it accepted for assertions.
public final class MockCaptureSubmissionService: CaptureSubmissionService {
    public nonisolated struct SubmissionFailed: Error, Equatable {
        public init() {}
    }

    public var delay: Duration
    /// Each submit while this is > 0 decrements it and throws.
    public var failuresRemaining: Int
    public private(set) var submissions: [CaptureSubmission] = []

    public init(delay: Duration = .milliseconds(600), failuresRemaining: Int = 0) {
        self.delay = delay
        self.failuresRemaining = failuresRemaining
    }

    public func submit(_ submission: CaptureSubmission) async throws {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw SubmissionFailed()
        }
        submissions.append(submission)
    }
}
#endif
