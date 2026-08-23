// Push Phase A (brewdesk#93) — the deep-link router is a plain observable
// value holder; this just pins its receive/consume contract.
import Testing
@testable import BrewDeskKit

@Suite @MainActor struct VisitReminderDeepLinkRouterTests {
    @Test func receiveSetsPendingVenueIDConsumeClearsIt() {
        let router = VisitReminderDeepLinkRouter()
        #expect(router.pendingVenueID == nil)

        router.receive(venueID: "v1")
        #expect(router.pendingVenueID == "v1")

        router.consume()
        #expect(router.pendingVenueID == nil)
    }
}
