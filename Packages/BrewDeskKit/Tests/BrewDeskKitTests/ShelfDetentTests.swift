import Testing
@testable import BrewDeskKit

/// The discovery shelf's detent grammar (brewdesk#76): where a resize drag
/// lands, how the adjacency used by the grabber's adjustable action chains,
/// and what the session remembers.
struct ShelfDetentTests {
    // MARK: - Drag resolution

    @Test func dragUnderHalfAStepSnapsBack() {
        #expect(ShelfDetent.resolve(from: .medium, projectedTranslation: 40) == .medium)
        #expect(ShelfDetent.resolve(from: .medium, projectedTranslation: -40) == .medium)
        #expect(ShelfDetent.resolve(from: .peek, projectedTranslation: -84) == .peek)
    }

    @Test func dragDownCollapsesOneStep() {
        #expect(ShelfDetent.resolve(from: .medium, projectedTranslation: 160) == .peek)
        #expect(ShelfDetent.resolve(from: .full, projectedTranslation: 160) == .medium)
    }

    @Test func dragUpExpandsOneStep() {
        #expect(ShelfDetent.resolve(from: .peek, projectedTranslation: -160) == .medium)
        #expect(ShelfDetent.resolve(from: .medium, projectedTranslation: -160) == .full)
    }

    @Test func hardFlingSkipsTheMiddleDetent() {
        #expect(ShelfDetent.resolve(from: .full, projectedTranslation: 600) == .peek)
        #expect(ShelfDetent.resolve(from: .peek, projectedTranslation: -600) == .full)
    }

    @Test func resolveClampsAtTheEnds() {
        #expect(ShelfDetent.resolve(from: .peek, projectedTranslation: 500) == .peek)
        #expect(ShelfDetent.resolve(from: .full, projectedTranslation: -500) == .full)
    }

    @Test func nonPositiveStepNeverMoves() {
        #expect(ShelfDetent.resolve(from: .medium, projectedTranslation: 500, step: 0) == .medium)
        #expect(ShelfDetent.resolve(from: .medium, projectedTranslation: 500, step: -10) == .medium)
    }

    // MARK: - Adjacency (grabber's accessibility adjustable action)

    @Test func expandedChainWalksPeekToFull() {
        #expect(ShelfDetent.peek.expanded == .medium)
        #expect(ShelfDetent.medium.expanded == .full)
        #expect(ShelfDetent.full.expanded == nil)
    }

    @Test func collapsedChainWalksFullToPeek() {
        #expect(ShelfDetent.full.collapsed == .medium)
        #expect(ShelfDetent.medium.collapsed == .peek)
        #expect(ShelfDetent.peek.collapsed == nil)
    }

    @Test func everyDetentDescribesItselfToAssistiveTech() {
        for detent in ShelfDetent.allCases {
            #expect(!detent.accessibilityValue.isEmpty)
        }
    }

    // MARK: - Session memory

    @Test func memoryStartsAtMediumTheClassicShelfShape() {
        #expect(ShelfDetentMemory(initial: .medium).last == .medium)
        #expect(ShelfDetentMemory().last == .medium)
    }

    @Test func memoryKeepsTheLastDetent() {
        let memory = ShelfDetentMemory()
        memory.last = .peek
        #expect(memory.last == .peek)
        memory.last = .full
        #expect(memory.last == .full)
    }
}
