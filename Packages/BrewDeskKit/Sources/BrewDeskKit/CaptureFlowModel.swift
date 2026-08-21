// Community capture prototype — flow state machine (brewdesk#46).
// This entire file compiles ONLY into Debug builds — the App Store binary
// contains none of it (Guideline 2.3.1). Spec: docs/community-capture-ux.md.
#if DEBUG
import SwiftUI
import UIKit

/// Drives guide → shoot(1…3) → confirm → submitted. Views render the stage;
/// all transition rules live here so they are unit-testable without UI.
@Observable
public final class CaptureFlowModel {
    public enum Stage: Equatable {
        case guide
        case shoot(stepIndex: Int)
        case confirm
        case submitted
    }

    public enum ShotResult: Equatable {
        case photo(UIImage)
        case skipped
    }

    public let venueID: String
    public let steps = CaptureShotKind.allCases
    public private(set) var stage: Stage = .guide
    public private(set) var results: [CaptureShotKind: ShotResult] = [:]
    public private(set) var isSubmitting = false
    public private(set) var submissionFailed = false
    /// Set while a single retake from Confirm is in flight: finishing the
    /// shot (photo, skip, or Back) returns straight to Confirm, not onward.
    private var returningToConfirm = false
    private let service: any CaptureSubmissionService

    public init(venueID: String, service: any CaptureSubmissionService) {
        self.venueID = venueID
        self.service = service
    }

    // MARK: Derived state

    public var currentKind: CaptureShotKind? {
        guard case .shoot(let index) = stage, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    public func result(for kind: CaptureShotKind) -> ShotResult? {
        results[kind]
    }

    /// True when cancelling would lose work (drives the discard alert).
    public var hasAnyPhoto: Bool {
        results.values.contains { if case .photo = $0 { true } else { false } }
    }

    public var photoCount: Int {
        results.values.count { if case .photo = $0 { true } else { false } }
    }

    /// "Next" on steps 1–2, "Review" on the last step (spec: the button
    /// names where it goes).
    public var advanceButtonTitle: String {
        if case .shoot(let index) = stage, index == steps.count - 1 || returningToConfirm {
            return "Review"
        }
        return "Next"
    }

    public var canAdvance: Bool {
        guard let kind = currentKind else { return false }
        return results[kind] != nil
    }

    public var canGoBack: Bool {
        if case .shoot = stage { return true }
        return false
    }

    // MARK: Transitions

    public func start() {
        stage = .shoot(stepIndex: 0)
    }

    /// Instant feedback: the photo lands in the slot; the user taps
    /// Next/Review to move on (or Retake to replace it).
    public func setPhoto(_ image: UIImage) {
        guard let kind = currentKind else { return }
        results[kind] = .photo(image)
    }

    public func retakeCurrentShot() {
        guard let kind = currentKind else { return }
        results[kind] = nil
    }

    /// Skip marks the slot honestly and advances immediately — one less tap.
    public func skipCurrentShot() {
        guard let kind = currentKind else { return }
        results[kind] = .skipped
        advance()
    }

    public func advance() {
        guard case .shoot(let index) = stage else { return }
        if returningToConfirm {
            returningToConfirm = false
            stage = .confirm
        } else if index + 1 < steps.count {
            stage = .shoot(stepIndex: index + 1)
        } else {
            stage = .confirm
        }
    }

    /// Back preserves the previous shot's result. From the first shot it
    /// returns to the guide; during a retake it cancels back to Confirm.
    public func goBack() {
        guard case .shoot(let index) = stage else { return }
        if returningToConfirm {
            returningToConfirm = false
            stage = .confirm
        } else if index == 0 {
            stage = .guide
        } else {
            stage = .shoot(stepIndex: index - 1)
        }
    }

    /// Confirm → one shot's Shoot step, then straight back to Confirm.
    public func retake(_ kind: CaptureShotKind) {
        guard stage == .confirm, let index = steps.firstIndex(of: kind) else { return }
        returningToConfirm = true
        stage = .shoot(stepIndex: index)
    }

    /// Photos are never lost on failure — the payload is rebuilt from
    /// `results`, which submit does not clear until success.
    public func submit() async {
        guard stage == .confirm, !isSubmitting else { return }
        isSubmitting = true
        submissionFailed = false
        defer { isSubmitting = false }
        do {
            try await service.submit(payload())
            stage = .submitted
        } catch {
            submissionFailed = true
        }
    }

    private func payload() -> CaptureSubmission {
        CaptureSubmission(
            venueID: venueID,
            shots: steps.map { kind in
                let data: Data? =
                    if case .photo(let image) = results[kind] {
                        image.jpegData(compressionQuality: 0.7)
                    } else {
                        nil
                    }
                return CaptureSubmission.Shot(kind: kind, imageData: data)
            }
        )
    }
}

/// Simulator/UI-test stand-in for the camera: a deterministic locally
/// rendered image per shot kind. No photo-library permission needed.
enum CaptureSamplePhoto {
    static func image(for kind: CaptureShotKind) -> UIImage {
        let size = CGSize(width: 900, height: 600)
        let colors: [CaptureShotKind: UIColor] = [
            .roomFromDoor: .systemBrown,
            .seatingArea: .systemTeal,
            .outlets: .systemIndigo,
        ]
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            (colors[kind] ?? .systemGray).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "Sample — \(kind.title)" as NSString
            text.draw(
                at: CGPoint(x: 40, y: 40),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 44),
                    .foregroundColor: UIColor.white,
                ]
            )
        }
    }
}
#endif
