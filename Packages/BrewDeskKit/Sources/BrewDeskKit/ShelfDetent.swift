import Foundation

/// The discovery shelf's honest resting positions (brewdesk#76).
///
/// The shelf's grabber used to be decoration over a fixed card; it now drives
/// three real detents. `peek` keeps just the filter chips over a mostly-bare
/// map, `medium` is the classic shelf (chips + the horizontal venue rail), and
/// `full` turns the rail into a scrolling vertical list.
///
/// Deliberately NOT presented with SwiftUI `.sheet`: the map lives inside a
/// `TabView`, and a modal sheet floats over the whole scene — including the
/// tab bar — at every detent, which would make tab switching impossible. The
/// shelf is an in-tab overlay card that borrows the sheet's detent grammar
/// instead (see `DiscoveryShelfCard`).
public enum ShelfDetent: String, CaseIterable, Sendable {
    case peek
    case medium
    case full

    /// The next detent up, or nil at `.full`.
    public var expanded: ShelfDetent? {
        switch self {
        case .peek: .medium
        case .medium: .full
        case .full: nil
        }
    }

    /// The next detent down, or nil at `.peek`.
    public var collapsed: ShelfDetent? {
        switch self {
        case .peek: nil
        case .medium: .peek
        case .full: .medium
        }
    }

    /// Read out to assistive tech as the grabber's adjustable value.
    public var accessibilityValue: String {
        switch self {
        case .peek: String(localized: "Collapsed")
        case .medium: String(localized: "Half height")
        case .full: String(localized: "Full height")
        }
    }

    /// Where a resize drag lands. `projectedTranslation` is the gesture's
    /// predicted end translation height (negative = upward = expand), so a
    /// short flick still changes detent and a hard fling from an end detent
    /// skips the middle one — matching `UISheetPresentationController` feel.
    /// `step` is the translation that counts as one detent hop; anything
    /// under half a step snaps back to where the drag started.
    public static func resolve(
        from current: ShelfDetent,
        projectedTranslation: CGFloat,
        step: CGFloat = 170
    ) -> ShelfDetent {
        guard step > 0, abs(projectedTranslation) >= step / 2 else { return current }
        let hops = min(2, max(1, Int((abs(projectedTranslation) / step).rounded())))
        let direction = projectedTranslation < 0 ? 1 : -1
        let all = Self.allCases
        guard let index = all.firstIndex(of: current) else { return current }
        let target = min(max(index + direction * hops, 0), all.count - 1)
        return all[target]
    }
}

/// Session-scoped detent memory (issue #76: "remember last"). The shelf
/// reopens at the detent the user left it for as long as the app runs;
/// deliberately not persisted to `UserDefaults` — a fresh launch starts at
/// `.medium`, the shelf's classic shape.
@Observable
public final class ShelfDetentMemory {
    public static let session = ShelfDetentMemory()

    public var last: ShelfDetent

    public init(initial: ShelfDetent = .medium) {
        self.last = initial
    }
}
