import Foundation

// BrewDesk's tenant identity (brewdesk#48, Apple 1.2 UGC compliance pack;
// re-pointed at the shared account platform by bamware-brewdesk#174, C9).
//
// Lives in VenueKit — not BrewDeskKit — because it is a wire-contract value
// consumed by more than the account stack: `UploadRailAPI` (community
// capture's Debug-only upload rail, dating-service v2) also stamps every
// request with it, and VenueKit cannot depend on BrewDeskKit (dependencies
// point inward, docs/ARCHITECTURE.md). `BrewDeskAccountTenant.id`
// (`BrewDeskKit/AccountComposition.swift`, the account platform's own
// tenant config) reads this same constant rather than repeating the
// literal, so there is exactly one place a typo could create a silent,
// isolated tenant partition on the auth service.

/// The one place BrewDesk's tenant identity lives. A typo here would silently
/// create a fresh, isolated tenant partition on the auth service — pinned by
/// package tests so it can never drift.
public enum BrewDeskTenant {
    public static let id = "bamware-brewdesk"
}
