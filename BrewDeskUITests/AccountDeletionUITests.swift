import XCTest

/// In-app account deletion (Apple 5.1.1(v), brewdesk#48) — Baat's two-step
/// double-confirm ported to BrewDesk. Fully mocked (`AuthScenarioService` +
/// in-memory session store), so unlike Baat's Maestro flow this CAN walk the
/// destructive path end-to-end: nothing real is deleted.
final class AccountDeletionUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "()",
        ]
        app.launch()

        // brewdesk#117: AccountScreen is now the You tab's root — no more
        // Saved-toolbar "Account entry" push.
        XCTAssertTrue(app.tabBars.buttons["tab-you"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-you"].tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: wait))

        type(app, into: "account-email-field", text: "tester@bamware.com")
        type(app, into: "account-password-field", text: "BrewDesk1!")
        element(app, "account-submit").tap()
        XCTAssertTrue(element(app, "account-signed-in").waitForExistence(timeout: wait))
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func type(_ app: XCUIApplication, into identifier: String, text: String) {
        let field = element(app, identifier)
        XCTAssertTrue(field.waitForExistence(timeout: wait))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func openDeletionScreen(_ app: XCUIApplication) {
        element(app, "account-delete-entry").tap()
        XCTAssertTrue(element(app, "account-delete-explain").waitForExistence(timeout: wait))
    }

    // MARK: - The destructive path (mocked end-to-end)

    @MainActor
    func testDeleteAccountWalksBothConfirmStepsAndSignsOut() {
        let app = launchSignedIn()
        openDeletionScreen(app)

        // Step 1: explain. The deletion list + retention disclosure.
        XCTAssertTrue(app.staticTexts["This cannot be undone"].exists)
        element(app, "account-delete-continue").tap()

        // Step 2: type-to-confirm.
        type(app, into: "account-delete-confirm-field", text: "DELETE")
        let confirm = element(app, "account-delete-confirm")
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        // Back on the account screen, signed out: the auth form is back.
        XCTAssertTrue(element(app, "account-submit").waitForExistence(timeout: wait))
        XCTAssertFalse(element(app, "account-signed-in").exists)

        // The account is really gone in the scenario auth world: signing in
        // again with the deleted credentials fails.
        type(app, into: "account-email-field", text: "tester@bamware.com")
        type(app, into: "account-password-field", text: "BrewDesk1!")
        element(app, "account-submit").tap()
        XCTAssertTrue(element(app, "account-error").waitForExistence(timeout: wait))
    }

    // MARK: - Gating + cancel

    @MainActor
    func testConfirmButtonStaysDisabledUntilConfirmWordTyped() {
        let app = launchSignedIn()
        openDeletionScreen(app)
        element(app, "account-delete-continue").tap()

        let confirm = element(app, "account-delete-confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: wait))
        XCTAssertFalse(confirm.isEnabled)

        // A wrong word keeps it disabled.
        type(app, into: "account-delete-confirm-field", text: "NOPE")
        XCTAssertFalse(confirm.isEnabled)
    }

    @MainActor
    func testCancelLeavesAccountIntact() {
        let app = launchSignedIn()
        openDeletionScreen(app)
        element(app, "account-delete-continue").tap()

        XCTAssertTrue(element(app, "account-delete-cancel").waitForExistence(timeout: wait))
        element(app, "account-delete-cancel").tap()

        // Still signed in — nothing was deleted.
        XCTAssertTrue(element(app, "account-signed-in").waitForExistence(timeout: wait))
    }
}
