// Community capture prototype — state-machine tests (brewdesk#46).
// The capture types compile only in Debug (Guideline 2.3.1); tests run in
// Debug, and the guard keeps a Release test build compiling to an empty file.
#if DEBUG
import Testing
import UIKit

@testable import BrewDeskKit

@Suite @MainActor struct CaptureFlowModelTests {
    private let service: MockCaptureSubmissionService
    private let model: CaptureFlowModel

    init() {
        service = MockCaptureSubmissionService(delay: .zero)
        model = CaptureFlowModel(venueID: "venue-1", service: service)
    }

    private func photo() -> UIImage {
        CaptureSamplePhoto.image(for: .roomFromDoor)
    }

    @Test func happyPathWalksGuideShootConfirmSubmitted() async {
        #expect(model.stage == .guide)
        model.start()
        #expect(model.stage == .shoot(stepIndex: 0))

        for index in 0..<3 {
            #expect(model.stage == .shoot(stepIndex: index))
            #expect(!model.canAdvance, "Next must be disabled before a photo lands")
            model.setPhoto(photo())
            #expect(model.canAdvance)
            model.advance()
        }

        #expect(model.stage == .confirm)
        await model.submit()
        #expect(model.stage == .submitted)
        #expect(service.submissions.count == 1)
        #expect(service.submissions.first?.venueID == "venue-1")
        #expect(service.submissions.first?.shots.count == 3)
    }

    @Test func advanceButtonNamesWhereItGoes() {
        model.start()
        #expect(model.advanceButtonTitle == "Next")
        model.setPhoto(photo())
        model.advance()
        #expect(model.advanceButtonTitle == "Next")
        model.setPhoto(photo())
        model.advance()
        #expect(model.advanceButtonTitle == "Review", "Last step's button says Review")
    }

    @Test func skipMarksSlotHonestlyAndAdvances() async {
        model.start()
        model.setPhoto(photo())
        model.advance()
        model.setPhoto(photo())
        model.advance()
        model.skipCurrentShot()
        #expect(model.stage == .confirm)
        #expect(model.result(for: .outlets) == .skipped)

        await model.submit()
        let shots = service.submissions.first?.shots
        #expect(shots?.last?.imageData == nil, "Skipped shot travels as nil data, not dropped")
        #expect(shots?.last?.kind == .outlets)
        #expect(shots?.first?.imageData != nil)
    }

    @Test func backPreservesPhotosAndReachesGuide() {
        model.start()
        model.setPhoto(photo())
        model.advance()
        #expect(model.stage == .shoot(stepIndex: 1))
        model.goBack()
        #expect(model.stage == .shoot(stepIndex: 0))
        #expect(model.result(for: .roomFromDoor) != nil, "Back keeps the earlier photo")
        model.goBack()
        #expect(model.stage == .guide)
    }

    @Test func retakeFromConfirmReturnsStraightToConfirm() {
        model.start()
        for _ in 0..<3 {
            model.setPhoto(photo())
            model.advance()
        }
        #expect(model.stage == .confirm)

        model.retake(.seatingArea)
        #expect(model.stage == .shoot(stepIndex: 1))
        model.setPhoto(photo())
        model.advance()
        #expect(model.stage == .confirm, "Retake returns to Confirm, not onward")

        model.retake(.outlets)
        model.goBack()
        #expect(model.stage == .confirm, "Backing out of a retake cancels to Confirm")
    }

    @Test func failedSubmitKeepsPhotosAndRetrySucceeds() async {
        service.failuresRemaining = 1
        model.start()
        for _ in 0..<3 {
            model.setPhoto(photo())
            model.advance()
        }

        await model.submit()
        #expect(model.stage == .confirm, "Failure stays on Confirm")
        #expect(model.submissionFailed)
        #expect(model.photoCount == 3, "Photos are never lost on failure")

        await model.submit()
        #expect(model.stage == .submitted)
        #expect(!model.submissionFailed)
        #expect(service.submissions.count == 1)
    }

    @Test func discardGuardTracksPhotos() {
        #expect(!model.hasAnyPhoto)
        model.start()
        model.skipCurrentShot()
        #expect(!model.hasAnyPhoto, "Skips alone lose nothing — no discard alert")
        model.setPhoto(photo())
        #expect(model.hasAnyPhoto)
    }
}
#endif
