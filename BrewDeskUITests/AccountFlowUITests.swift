import XCTest

/// Optional accounts (brewdesk#48, Apple 1.2). Deterministic via
/// `-UITestScenario`: auth resolves to the in-process `AuthScenarioService`
/// (seeded `tester@bamware.com` / `BrewDesk1!`) and the session store is
/// in-memory, so every launch starts signed out. Entry point: the Saved tab
/// toolbar ("account-entry").
final class AccountFlowUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "()",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // brewdesk#117: AccountScreen is now the You tab's root — no more
    // Saved-toolbar "Account entry" push. Matched by label via `youTab`
    // (brewdesk#131): the floating tab bar attaches identifiers seconds
    // after launch, which made every test here fail at this first wait.
    @MainActor
    private func openAccount(_ app: XCUIApplication) {
        XCTAssertTrue(app.youTab.waitForExistence(timeout: wait))
        app.youTab.tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: wait))
    }

    @MainActor
    private func type(_ app: XCUIApplication, into identifier: String, text: String) {
        let field = element(app, identifier)
        XCTAssertTrue(field.waitForExistence(timeout: wait))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func signInSeeded(_ app: XCUIApplication) {
        type(app, into: "account-email-field", text: "tester@bamware.com")
        type(app, into: "account-password-field", text: "BrewDesk1!")
        element(app, "account-submit").tap()
        XCTAssertTrue(element(app, "account-signed-in").waitForExistence(timeout: wait))
    }

    // MARK: - Anonymous still works (accounts must gate nothing today)

    @MainActor
    func testAnonymousBrowsingWorksWithoutAnyAccount() {
        let app = launch()

        // Browse venues — no sign-in, no gate.
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))

        // Saved tab renders (empty state) without forcing an account.
        app.savedTab.tap()
        XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait))

        // You tab is there too — offered, never forced.
        app.youTab.tap()
        XCTAssertTrue(element(app, "account-mode-toggle").waitForExistence(timeout: wait))
    }

    // MARK: - Sign up → sign out → sign in

    @MainActor
    func testSignUpSignOutSignInRoundTrip() {
        let app = launch()
        openAccount(app)

        // Create an account.
        app.buttons["Create Account"].firstMatch.tap()
        type(app, into: "account-name-field", text: "New Taster")
        type(app, into: "account-email-field", text: "new@bamware.com")
        type(app, into: "account-password-field", text: "FlatWhite11!")
        element(app, "account-submit").tap()

        let signedIn = element(app, "account-signed-in")
        XCTAssertTrue(signedIn.waitForExistence(timeout: wait))
        XCTAssertTrue(signedIn.label.contains("new@bamware.com"))

        // Sign out returns to the signed-out form.
        element(app, "account-sign-out").tap()
        XCTAssertTrue(element(app, "account-submit").waitForExistence(timeout: wait))

        // Sign back in as the registered account (in-process auth world).
        type(app, into: "account-email-field", text: "new@bamware.com")
        type(app, into: "account-password-field", text: "FlatWhite11!")
        element(app, "account-submit").tap()
        XCTAssertTrue(element(app, "account-signed-in").waitForExistence(timeout: wait))
    }

    // MARK: - Failure path

    @MainActor
    func testWrongPasswordShowsFriendlyErrorAndStaysSignedOut() {
        let app = launch()
        openAccount(app)

        type(app, into: "account-email-field", text: "tester@bamware.com")
        type(app, into: "account-password-field", text: "WrongPass99!")
        element(app, "account-submit").tap()

        XCTAssertTrue(element(app, "account-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Invalid email or password."].exists)
        XCTAssertFalse(element(app, "account-signed-in").exists)
    }

    // MARK: - Contact & content rules (Apple 1.2: published contact method)

    @MainActor
    func testPoliciesScreenPublishesContactAndRules() {
        let app = launch()
        openAccount(app)

        element(app, "account-policies-entry").tap()
        XCTAssertTrue(app.navigationBars["Contact & Content Rules"].waitForExistence(timeout: wait))

        let contact = element(app, "account-contact-email")
        XCTAssertTrue(contact.waitForExistence(timeout: wait))
        XCTAssertTrue(contact.label.contains("bmalik.ee@gmail.com"))
        XCTAssertTrue(element(app, "account-content-rules").exists)
    }
}
