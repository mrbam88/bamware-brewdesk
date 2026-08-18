import Foundation

struct AppConfiguration: Sendable {
    let appName: String
    let tagline: String
    let termsURL: URL
    let privacyURL: URL
    let supportURL: URL

    static let brewDesk = AppConfiguration(
        appName: "BrewDesk",
        tagline: "Find a cafe where the Wi-Fi works and laptops are welcome.",
        termsURL: URL(string: "https://bamware.io/brewdesk/terms")!,
        privacyURL: URL(string: "https://bamware.io/brewdesk/privacy")!,
        supportURL: URL(string: "https://bamware.io/brewdesk/support")!
    )
}
