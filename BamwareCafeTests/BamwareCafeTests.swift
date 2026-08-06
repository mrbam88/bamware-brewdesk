import Foundation
import StoreKitTest
import Testing
@testable import BamwareCafe

@Suite struct JWTClaimsDecoderTests {
    @Test func decodesBase64URLClaims() throws {
        let token = try token(payload: [
            "userId": "user-cafe",
            "email": "worker@example.com",
            "name": "Cafe Worker",
            "role": "customer",
            "tenantId": "bamware-cafe",
            "emailVerified": true,
            "exp": 4_000_000_000,
        ])

        let claims = try JWTClaimsDecoder.decode(token)

        #expect(claims.userId == "user-cafe")
        #expect(claims.tenantId == "bamware-cafe")
        #expect(claims.emailVerified == true)
    }

    @Test func rejectsMalformedToken() {
        #expect(throws: AuthError.invalidSession) {
            try JWTClaimsDecoder.decode("not-a-jwt")
        }
    }

    private func token(payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}

@Suite @MainActor struct AppFlowStoreTests {
    @Test func persistsCompletedGates() {
        let suite = "AppFlowStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppFlowStore(defaults: defaults)
        #expect(!store.onboardingComplete)
        #expect(!store.locationIntroComplete)

        store.finishOnboarding()
        store.finishLocationIntro()

        let restored = AppFlowStore(defaults: defaults)
        #expect(restored.onboardingComplete)
        #expect(restored.locationIntroComplete)
    }
}

@Suite struct ReleaseConfigurationTests {
    @Test func usesBrewDeskIdentityAndCanonicalURLs() {
        let configuration = AppConfiguration.cafe

        #expect(configuration.appName == "BrewDesk")
        #expect(configuration.termsURL.absoluteString == "https://bamware.io/brewdesk/terms")
        #expect(configuration.privacyURL.absoluteString == "https://bamware.io/brewdesk/privacy")
        #expect(configuration.supportURL.absoluteString == "https://bamware.io/brewdesk/support")
    }
}

@Suite(.serialized) struct StoreKitConfigurationTests {
    @Test func loadsMonthlyAndAnnualProducts() throws {
        _ = try SKTestSession(configurationFileNamed: "Products")
        let url = try #require(Bundle.main.url(forResource: "Products", withExtension: "storekit"))
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(root["subscriptionGroups"] as? [[String: Any]])
        let identifiers = groups
            .flatMap { ($0["subscriptions"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["productID"] as? String }

        #expect(Set(identifiers) == [
            "bamware.BamwareCafe.pro.monthly",
            "bamware.BamwareCafe.pro.annual",
        ])
    }
}
