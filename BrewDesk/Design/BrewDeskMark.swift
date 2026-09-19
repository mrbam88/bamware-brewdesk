import SwiftUI
import BrewDeskKit

/// The vector BrewDesk mark lives in `BrewDeskKit` (bamware-brewdesk#186) so
/// it can be reused from the package's own screens as well as from here —
/// same `typealias AppBrand = BrewDeskPalette` pattern already used in this
/// file's neighbor for the same reason.
///
/// `BrewDeskMark.Mode.signal` (the idle, looping "finding cafés" variant)
/// is implemented but deliberately NOT wired into any screen yet: the only
/// live venues-loading state, `CafeMapScreen`'s "Finding work spots…"
/// `ProgressView`, is fenced off in this ticket (another agent's active
/// work); the one other candidate, `CafeListScreen`, is dead/unreachable
/// code (see `ReviewerSimulationTests.swift`'s "now only renders on the
/// unreachable CafeListScreen" and its own absent call site) — wiring the
/// signal mode there would animate something nobody can see. Per the
/// ticket's own "if no such state exists, skip this and say so" clause.
typealias BrewDeskMark = BrewDeskKit.BrewDeskMark

/// Overlays the vector mark at 50% opacity on the real `LaunchMark` raster
/// asset so a geometry drift is visible at a glance. Alignment was checked
/// this way while tuning `BrewDeskMarkGeometry`'s constants (see that type's
/// doc comment) — cup body, dot, and saucer land almost exactly on the
/// asset; the arcs and handle are close but not pixel-identical, which is
/// fine for an animated mark judged in motion rather than as a static diff.
#Preview("Overlay alignment check") {
    ZStack {
        Color("LaunchBackground")
        Image("LaunchMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(60)
        BrewDeskMark(tint: .white, mode: .settled)
            .padding(60)
            .opacity(0.5)
    }
    .ignoresSafeArea()
}

#Preview("Settled") {
    ZStack {
        Color("LaunchBackground")
        BrewDeskMark(tint: .white, mode: .settled)
            .padding(60)
    }
    .ignoresSafeArea()
}

#Preview("Idle signal") {
    ZStack {
        AppBrand.page
        BrewDeskMark(mode: .signal)
            .padding(60)
    }
    .ignoresSafeArea()
}
