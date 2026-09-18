import XCTest

/// In-app account deletion (Apple 5.1.1(v), brewdesk#48) — re-pointed at the
/// shared `BamwareAccountUI` package's `AccountDeletionScreen` for
/// bamware-brewdesk#174 (C9). Fully mocked (`AuthScenarioService` + in-memory
/// session store), so unlike Baat's Maestro flow this CAN walk the
/// destructive path end-to-end: nothing real is deleted.
final class AccountDeletionUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

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
        XCTAssertTrue(app.youTab.waitForExistence(timeout: wait))
        app.youTab.tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: wait))

        element(app, "account-entry").tap()
        let continueWithEmail = element(app, "account-sign-in-email")
        XCTAssertTrue(continueWithEmail.waitForExistence(timeout: wait))
        continueWithEmail.tap()
        type(app, into: "account-sign-in-email-field", text: "tester@bamware.com")
        type(app, into: "account-sign-in-password-field", text: "Tester1!")
        element(app, "account-sign-in-submit").tap()

        // Success auto-dismisses the sign-in sheet back to the You tab.
        let entry = element(app, "account-entry")
        XCTAssertTrue(entry.waitForExistence(timeout: wait))
        entry.tap()
        XCTAssertTrue(element(app, "account-signed-in").waitForExistence(timeout: wait))
        return app
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

        // Step 2: type-to-confirm. The package's final destructive trigger
        // is `account-delete` (not the pre-lift app's `account-delete-confirm`).
        type(app, into: "account-delete-confirm-field", text: "DELETE")
        let confirm = element(app, "account-delete")
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        // Deletion clears the session, which auto-dismisses the whole
        // Account sheet stack back to the You tab.
        let entry = element(app, "account-entry")
        XCTAssertTrue(entry.waitForExistence(timeout: wait))
        entry.tap()
        let continueWithEmail = element(app, "account-sign-in-email")
        XCTAssertTrue(continueWithEmail.waitForExistence(timeout: wait))
        continueWithEmail.tap()

        // The account is really gone in the scenario auth world: signing in
        // again with the deleted credentials fails.
        type(app, into: "account-sign-in-email-field", text: "tester@bamware.com")
        type(app, into: "account-sign-in-password-field", text: "Tester1!")
        element(app, "account-sign-in-submit").tap()
        XCTAssertTrue(element(app, "account-sign-in-error").waitForExistence(timeout: wait))
    }

    // MARK: - Gating + cancel

    @MainActor
    func testConfirmButtonStaysDisabledUntilConfirmWordTyped() {
        let app = launchSignedIn()
        openDeletionScreen(app)
        element(app, "account-delete-continue").tap()

        let confirm = element(app, "account-delete")
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
