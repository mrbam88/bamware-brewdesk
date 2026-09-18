import XCTest

/// Optional accounts (brewdesk#48, Apple 1.2; re-pointed at the shared
/// `BamwareAccountUI` package's screens for bamware-brewdesk#174, C9).
/// Deterministic via `-UITestScenario`: auth resolves to the in-process
/// `AuthScenarioService` (seeded `tester@bamware.com` / `Tester1!`) and the
/// session store is in-memory, so every launch starts signed out. Entry
/// point: the You tab's "Your account" row opens a sheet hosting the
/// package's `SignInScreen`/`AccountScreen`.
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

    /// Taps the "Your account" row (signed out: "Sign In or Create
    /// Account") to open the package's `SignInScreen` sheet.
    @MainActor
    private func openSignIn(_ app: XCUIApplication) {
        openAccount(app)
        let entry = element(app, "account-entry")
        XCTAssertTrue(entry.waitForExistence(timeout: wait))
        entry.tap()
        XCTAssertTrue(element(app, "account-sign-in-header").waitForExistence(timeout: wait))
    }

    @MainActor
    private func type(_ app: XCUIApplication, into identifier: String, text: String) {
        let field = element(app, identifier)
        XCTAssertTrue(field.waitForExistence(timeout: wait))
        field.tap()
        field.typeText(text)
    }

    /// Reveals the package's email/password form behind "Continue with
    /// Email" — the package's low-emphasis path (Apple/Google are the
    /// default), matching `SignInScreen`'s documented shape.
    @MainActor
    private func revealEmailForm(_ app: XCUIApplication) {
        let continueWithEmail = element(app, "account-sign-in-email")
        XCTAssertTrue(continueWithEmail.waitForExistence(timeout: wait))
        continueWithEmail.tap()
        XCTAssertTrue(element(app, "account-sign-in-email-field").waitForExistence(timeout: wait))
    }

    @MainActor
    private func signInSeeded(_ app: XCUIApplication) {
        revealEmailForm(app)
        type(app, into: "account-sign-in-email-field", text: "tester@bamware.com")
        type(app, into: "account-sign-in-password-field", text: "Tester1!")
        element(app, "account-sign-in-submit").tap()
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
        openAccount(app)
        XCTAssertTrue(element(app, "account-entry").exists)
    }

    // MARK: - Sign in with Apple / Google appear at equal prominence

    @MainActor
    func testSignInScreenOffersAppleAtEqualProminenceToGoogleAndEmail() {
        // GIDClientID is configured (vault /bamware/brewdesk/google-ios-client-id,
        // 2026-09-19), so Google is offered — and Guideline 4.8 requires Apple
        // beside it at equal prominence (`SocialButtonsLayout` enforces the
        // pairing; this pins the rendered result). Never tapped here: both
        // present real system sheets XCUITest cannot drive deterministically.
        let app = launch()
        openSignIn(app)
        let apple = element(app, "account-sign-in-apple")
        let google = element(app, "account-sign-in-google")
        XCTAssertTrue(apple.waitForExistence(timeout: wait))
        XCTAssertTrue(google.waitForExistence(timeout: wait), "Google button missing although GIDClientID is configured")
        XCTAssertEqual(apple.frame.width, google.frame.width, accuracy: 1, "Apple and Google buttons must be the same width (4.8)")
        XCTAssertEqual(apple.frame.height, google.frame.height, accuracy: 1, "Apple and Google buttons must be the same height (4.8)")
        XCTAssertTrue(element(app, "account-sign-in-email").exists)
        // BrewDesk's own copy sits above the package's sign-in form.
        XCTAssertTrue(element(app, "account-sign-in-value-prop").exists)
    }

    // MARK: - Sign up → sign out → sign in

    @MainActor
    func testSignUpSignOutSignInRoundTrip() {
        let app = launch()
        openSignIn(app)
        revealEmailForm(app)

        // Create an account.
        element(app, "account-sign-in-mode-toggle").tap()
        type(app, into: "account-sign-in-name-field", text: "New Taster")
        type(app, into: "account-sign-in-email-field", text: "new@bamware.com")
        type(app, into: "account-sign-in-password-field", text: "FlatWhite11!")
        element(app, "account-sign-in-submit").tap()

        // Success dismisses the sign-in sheet back to the You tab, whose
        // "Your account" row now opens the signed-in `AccountScreen`.
        let entry = element(app, "account-entry")
        XCTAssertTrue(entry.waitForExistence(timeout: wait))
        entry.tap()
        let signedIn = element(app, "account-signed-in")
        XCTAssertTrue(signedIn.waitForExistence(timeout: wait))
        XCTAssertTrue(signedIn.label.contains("new@bamware.com"))

        // Sign out: the sheet auto-dismisses (no longer signed in).
        element(app, "account-sign-out").tap()
        XCTAssertTrue(entry.waitForExistence(timeout: wait))

        // Sign back in as the registered account (in-process auth world).
        entry.tap()
        revealEmailForm(app)
        type(app, into: "account-sign-in-email-field", text: "new@bamware.com")
        type(app, into: "account-sign-in-password-field", text: "FlatWhite11!")
        element(app, "account-sign-in-submit").tap()
        entry.tap()
        XCTAssertTrue(element(app, "account-signed-in").waitForExistence(timeout: wait))
    }

    // MARK: - Failure path

    @MainActor
    func testWrongPasswordShowsFriendlyErrorAndStaysSignedOut() {
        let app = launch()
        openSignIn(app)
        revealEmailForm(app)

        type(app, into: "account-sign-in-email-field", text: "tester@bamware.com")
        type(app, into: "account-sign-in-password-field", text: "WrongPass99!")
        element(app, "account-sign-in-submit").tap()

        XCTAssertTrue(element(app, "account-sign-in-error").waitForExistence(timeout: wait))
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
