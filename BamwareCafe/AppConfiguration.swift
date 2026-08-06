import Foundation

struct AppConfiguration: Sendable {
    let tenantID: String
    let appName: String
    let tagline: String
    let authBaseURL: URL
    let termsURL: URL
    let privacyURL: URL
    let supportURL: URL
    let monthlyProductID: String
    let annualProductID: String

    static let cafe = AppConfiguration(
        tenantID: "bamware-cafe",
        appName: "BrewDesk",
        tagline: "Find a cafe where the Wi-Fi works and laptops are welcome.",
        authBaseURL: URL(string: "https://cje3ppxv47.execute-api.us-east-1.amazonaws.com")!,
        termsURL: URL(string: "https://bamware.io/brewdesk/terms")!,
        privacyURL: URL(string: "https://bamware.io/brewdesk/privacy")!,
        supportURL: URL(string: "https://bamware.io/brewdesk/support")!,
        monthlyProductID: "bamware.BamwareCafe.pro.monthly",
        annualProductID: "bamware.BamwareCafe.pro.annual"
    )
}
