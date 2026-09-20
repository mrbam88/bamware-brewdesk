import BamwareUI
import MapKit
import StoreKit
import SwiftUI
import VenueKit

public struct VenueDetailScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.venuePhotoService) private var photoService
    @Environment(\.openURL) private var openURL
    @Environment(\.launchEnvironment) private var launchEnvironment
    @Environment(\.requestReview) private var requestReview
    private let venue: Venue
    @Bindable private var savedVenues: SavedVenuesStore
    @State private var photos: [VenuePhoto] = []
    @State private var expandedPhoto: VenuePhoto?
    @State private var photoLoad: PhotoLoad = .loading
    @State private var photoAttempt = 0
    @State private var failedThumbnailURLs: Set<String> = []
    // bd#197: the nav bar shows no title while the hero's own name is
    // visible, and only picks it up once that name has scrolled out from
    // under the nav bar — see `heroNameFrame` name on `hero`.
    @State private var showNavTitle = false
    #if DEBUG
        @State private var showCaptureFlow = false
    #endif

    private enum PhotoLoad { case loading, loaded, failed }

    public init(venue: Venue, savedVenues: SavedVenuesStore) {
        self.venue = venue
        self.savedVenues = savedVenues
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero
                photoSection
                workability
                businessInfo
                pressLinks
                // Structured observation entry (brewdesk#47) — the section
                // owns its sheet and service resolution; ships in Release.
                // brewdesk#174 (C9): the store-submission surface gate is
                // gone — accounts, report/block, and this entry now ship in
                // every build. The submitted per-install UUID is declared
                // in the App Privacy label (submission/1.1/metadata/
                // privacy-label.md).
                ObservationFormEntrySection(venue: venue)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            // The action dock is a bottom `safeAreaInset`, so the scroll
            // content is already inset by its exact (Dynamic Type-aware)
            // height — the old fixed 100pt under-cleared tall docks and
            // double-padded short ones (ui-review-2026-08-21 finding 6).
            .padding(.bottom, 24)
        }
        // Named space for `heroNameFrame`'s preference below — scrolling
        // this ScrollView is what moves the hero name's reported frame.
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(HeroNameFramePreferenceKey.self) { maxY in
            // The hero name has scrolled out from under the (invisible) nav
            // bar once its bottom edge passes y = 0 in the scroll's own
            // coordinate space — that's the moment the nav bar picks up the
            // title so the screen is never left with no name showing at all.
            showNavTitle = maxY < 0
        }
        .accessibilityIdentifier("venue-detail-screen")
        .background(theme.backgroundColor.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actionDock }
        // bd#119 led to bd#142: printing the venue name a second time as
        // a permanent nav title duplicated the hero's own name in screenshot
        // QA. bd#197 fixes that the other way around — the hero card now
        // shows the real, visible name, and the nav title only appears
        // (still inline, never duplicated on screen) once that name has
        // scrolled out of view, so there's always exactly one name visible.
        .navigationTitle(showNavTitle ? venue.name : "")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
            // Community capture prototype entry (brewdesk#46). Debug-only:
            // the App Store binary contains no capture UI (Guideline 2.3.1).
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCaptureFlow = true
                    } label: {
                        Label("Add photos", systemImage: "camera")
                    }
                    .accessibilityIdentifier("capture-entry")
                }
            }
            .sheet(isPresented: $showCaptureFlow) {
                CaptureFlowScreen(venue: venue, service: MockCaptureSubmissionService())
            }
        #endif
        .task(id: photoAttempt) {
            guard let photoService else { return }
            photoLoad = .loading
            do {
                photos = try await photoService.fetchPhotos(venueId: venue.id)
                photoLoad = .loaded
            } catch is CancellationError {
                // View went away; nothing to show.
            } catch {
                guard !Task.isCancelled else { return }
                photoLoad = .failed
            }
        }
    }

    /// Photos are optional content: while loading, or when the engine has none,
    /// the section collapses (no layout jump for the common case — same policy
    /// as the stat strip). A *failed* fetch is different: it gets a compact,
    /// intentional row with a Retry, never a silent gap.
    @ViewBuilder
    private var photoSection: some View {
        switch photoLoad {
        case .loaded where !photos.isEmpty:
            photoStrip
        case .failed:
            photoStripError
        default:
            EmptyView()
        }
    }

    private var photoStripError: some View {
        HStack(spacing: 10) {
            Label("Photos unavailable", systemImage: "photo")
                .font(.footnote)
            Spacer(minLength: 0)
            // 44pt minimum touch target + footnote type: the caption-sized
            // text button failed the accessibility audit (hit region + text
            // size) once detail began presenting as a sheet (brewdesk#117).
            Button("Retry") { photoAttempt += 1 }
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("photos-retry")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo-strip-error")
    }

    /// Display-only venue photos. Google thumbnails omit author attribution
    /// (Places policy allows this for space-limited galleries) BECAUSE the
    /// tap-to-expand viewer shows the full attribution — keep both in sync.
    /// Community photos (brewdesk#49) instead carry their contributor byline
    /// right on the thumbnail — our own attribution UI, mirrored fullscreen.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(photos) { photo in
                    let thumbnailFailed = failedThumbnailURLs.contains(photo.url)
                    Button {
                        expandedPhoto = photo
                    } label: {
                        AsyncImage(url: URL(string: photo.url)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                // Unloadable image: a glyph, not a forever-grey
                                // rectangle. Still tappable — the viewer has Retry.
                                ZStack {
                                    Rectangle().fill(.quaternary)
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                                .onAppear { failedThumbnailURLs.insert(photo.url) }
                            default:
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .frame(width: 210, height: 140)
                        .overlay(alignment: .bottomLeading) {
                            if let byline = photo.communityByline {
                                photoBylineBadge(byline)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        // Reuses the two existing localized keys ("Photo of %@",
                        // "Photo by %@") — no new catalog entries.
                        photo.communityByline.map {
                            Text("Photo of \(venue.name)") + Text(verbatim: ", ") + Text("Photo by \($0)")
                        } ?? Text("Photo of \(venue.name)")
                    )
                    .accessibilityValue(thumbnailFailed ? Text("Photo unavailable") : Text(verbatim: ""))
                    .accessibilityHint(Text("Opens the full-size photo"))
                    .accessibilityIdentifier(thumbnailFailed ? "photo-thumb-failed" : "photo-thumb")
                }
            }
        }
        .frame(height: 140)
        .accessibilityIdentifier("venue-photo-strip")
        .sheet(item: $expandedPhoto) { photo in
            PhotoViewer(photo: photo, venueName: venue.name)
        }
    }

    /// Contributor byline chip on a community thumbnail (brewdesk#49): white
    /// caption on a dark scrim so contrast holds over any photo content.
    /// VoiceOver reads the byline through the button's label — the visual
    /// chip itself stays out of the accessibility tree (no double read).
    private func photoBylineBadge(_ byline: String) -> some View {
        Text("Photo by \(byline)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(8)
            .accessibilityHidden(true)
    }

    /// Named coordinate space the hero name's frame is measured in
    /// (`heroNameFrame`) — declared on the outer `ScrollView`.
    private static let scrollSpace = "venueDetailScroll"

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            // bd#197: the card's own heading — real, visible, on-screen
            // text, not a zero-size VoiceOver-only proxy (that was bd#142's
            // fix for a different problem: a *second* large copy duplicating
            // the nav title). Without this the largest text on the card was
            // `locationSummary`'s neighborhood line, which read as the
            // title — "it just says Greenwich Village" was the bug report.
            Text(venue.name)
                .font(.title2.weight(.bold))
                // 2-line cap (+ `.minimumScaleFactor`) at standard sizes
                // keeps the card compact; a real long name ("Stavros
                // Niarchos Foundation Library") still clipped there even at
                // 3 lines once Dynamic Type reached accessibility sizes
                // (caught by `performAccessibilityAudit(.textClipped)`), so
                // at those sizes the cap lifts entirely — the card simply
                // grows, never truncates, matching how `businessInfo`'s
                // hours block already has no hard line cap.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("venue-detail-heading")
                .background(heroNameFrame)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ScoreBadge(venue: venue)
                    locationSummary
                }
                VStack(alignment: .leading, spacing: 10) {
                    ScoreBadge(venue: venue)
                    locationSummary
                }
            }

            if venue.displayScore == nil {
                unobservedExplanation
            }

            if !venue.vibeTags.isEmpty {
                VibeChips(tags: venue.vibeTags)
            }

            NavigationLink {
                MethodologyScreen()
            } label: {
                // ≥44pt hit region + espresso at footnote size: passes the
                // accessibility audit (hit area + contrast on foam) — bd#36.
                Label("How scoring works", systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.primaryColor)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("methodology-link")
        }
        .padding(20)
        .background(BrewDeskPalette.foam.opacity(colorScheme == .dark ? 0.08 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(BrewDeskPalette.espresso.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// One-line honesty note for a venue with no real evidence behind its
    /// score (bd#159): `workScore` is the engine's flat neutral fallback
    /// (ve#64), not a measurement. The "Been here? Rate it." half points at
    /// `ObservationFormEntrySection` below, where that rating actually
    /// happens; this line does not add a second entry point. Unconditional
    /// since brewdesk#174 (C9) removed the store-submission surface gate
    /// this used to check.
    private var unobservedExplanation: some View {
        Text(unobservedExplanationText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("unobserved-explanation")
    }

    private var unobservedExplanationText: String {
        String(localized: "We haven't checked this one yet.")
            + " " + String(localized: "Been here? Rate it.")
    }

    /// Reports the hero name's frame (bottom edge, specifically) up through
    /// `HeroNameFramePreferenceKey` so the ScrollView's `onPreferenceChange`
    /// can decide when the nav title should take over — iOS 17-safe
    /// (`onScrollVisibilityChange` is iOS 18+, this deployment target is 17).
    private var heroNameFrame: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: HeroNameFramePreferenceKey.self,
                value: proxy.frame(in: .named(Self.scrollSpace)).maxY
            )
        }
    }

    /// Demoted, address-flavored secondary line under the hero name
    /// (bd#197) — `.subheadline`/`.secondary` throughout, never `.headline`,
    /// so nothing here competes with the venue name for "this is the title."
    /// The street line carries a small pin glyph so it reads as an address
    /// rather than a second line of title.
    private var locationSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(venue.neighborhood) · \(venue.borough)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let address = venue.address {
                Label {
                    Text(address)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var workability: some View {
        let cardStamp = workabilityCardStamp
        return informationCard(
            title: "Workability",
            systemImage: "checkmark.seal",
            subtitle: ClaimRow.provenanceLine(for: cardStamp)
        ) {
            VStack(spacing: 14) {
                ClaimRow(title: "Wi-Fi", systemImage: "wifi", claim: venue.attributes.wifi, cardStampClaim: cardStamp)
                Divider()
                ClaimRow(
                    title: "Outlets",
                    systemImage: "powerplug",
                    claim: venue.attributes.outlets,
                    cardStampClaim: cardStamp
                )
                Divider()
                ClaimRow(
                    title: "Laptop policy",
                    systemImage: "laptopcomputer",
                    claim: venue.attributes.laptopPolicy,
                    cardStampClaim: cardStamp
                )
                Divider()
                ClaimRow(
                    title: "Noise",
                    systemImage: "speaker.wave.2",
                    claim: venue.attributes.noise,
                    cardStampClaim: cardStamp
                )
            }
        }
    }

    /// The Workability card's single provenance stamp (brewdesk#119): the
    /// claim value (source, confidence, date) shared by the most rows —
    /// ties break toward Wi-Fi's order (wifi, outlets, laptop policy,
    /// noise), the same order the rows render in. A row whose own claim
    /// doesn't match this becomes the "disagrees" case and prints its own
    /// provenance line (`ClaimRow.agreesWithCardStamp`).
    private var workabilityCardStamp: Claim {
        let claims = [
            venue.attributes.wifi,
            venue.attributes.outlets,
            venue.attributes.laptopPolicy,
            venue.attributes.noise,
        ]
        struct ProvenanceKey: Hashable {
            let source: String
            let confidencePercent: Int
            let date: Substring
        }
        func key(for claim: Claim) -> ProvenanceKey {
            ProvenanceKey(
                source: claim.source,
                confidencePercent: claim.confidencePercent,
                date: claim.observedAt.prefix(10)
            )
        }
        var counts: [ProvenanceKey: Int] = [:]
        var order: [ProvenanceKey] = []
        for claim in claims {
            let claimKey = key(for: claim)
            if counts[claimKey] == nil { order.append(claimKey) }
            counts[claimKey, default: 0] += 1
        }
        // `max(by:)` keeps the first of equal elements, so a tie resolves
        // to whichever key `order` saw first — i.e. Wi-Fi's row order.
        let modeKey = order.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? order[0]
        return claims.first { key(for: $0) == modeKey } ?? claims[0]
    }

    // MARK: - Business info (brewdesk#50)

    /// Hours + website + phone in one card (email dropped per #80 — website
    /// is the link that matters). Collapses entirely when the venue carries
    /// none of the three (same policy as the photo strip).
    @ViewBuilder
    private var businessInfo: some View {
        if venue.hoursRaw != nil || websiteURL != nil || phoneURL != nil {
            informationCard(title: "Info", systemImage: "storefront") {
                VStack(alignment: .leading, spacing: 14) {
                    if let raw = venue.hoursRaw {
                        hoursBlock(raw: raw)
                    }
                    if let url = websiteURL {
                        if venue.hoursRaw != nil { Divider() }
                        websiteRow(url)
                    }
                    if let url = phoneURL, let number = venue.phone {
                        if venue.hoursRaw != nil || websiteURL != nil { Divider() }
                        callRow(url, number: number)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("business-info-card")
        }
    }

    // MARK: - In the press (bd#180)

    /// Allowlisted press links from the engine's `news[]` (ve#103). Additive,
    /// optional — hidden entirely when the venue carries no news (same
    /// collapse policy as `businessInfo`). Never an input to Work Fit; pure
    /// discovery. Each row opens the article in Safari; a malformed `url`
    /// from the wire is dropped rather than crashing or rendering a dead row.
    @ViewBuilder
    private var pressLinks: some View {
        let links = validPressLinks
        if !links.isEmpty {
            informationCard(title: "In the press", systemImage: "newspaper") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(links.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { Divider() }
                        pressLinkRow(entry.link, url: entry.url)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("press-links")
        }
    }

    private var validPressLinks: [(link: NewsLink, url: URL)] {
        (venue.news ?? []).compactMap { link in
            guard let url = URL(string: link.url) else { return nil }
            return (link, url)
        }
    }

    /// Source domain is always shown (the trust signal); the title, when
    /// present, sits above it. Title/domain come from allowlisted press
    /// copy the engine curates — unlike `Claim.detail`, safe to render
    /// verbatim (see `NewsLink` doc comment).
    private func pressLinkRow(_ link: NewsLink, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: link.displayTitle ?? link.sourceDomain)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.primaryColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if link.displayTitle != nil {
                            Text(verbatim: link.sourceDomain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } icon: {
                    Image(systemName: "newspaper")
                        .foregroundStyle(theme.primaryColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("press-link")
        .accessibilityHint("Opens the article in Safari")
    }

    /// Structured schedule with an open-now badge when the OSM string parses;
    /// otherwise the raw string exactly as served — a wrong open/closed claim
    /// is worse than no claim (see `OpeningHours`).
    @ViewBuilder
    private func hoursBlock(raw: String) -> some View {
        if let hours = OpeningHours.parse(raw) {
            VStack(alignment: .leading, spacing: 8) {
                openNowBadge(hours)
                ForEach(hours.dayGroups) { group in
                    dayGroupRow(group)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("business-hours-structured")
        } else {
            Text(raw)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("business-hours-raw")
        }
    }

    private func openNowBadge(_ hours: OpeningHours) -> some View {
        let isOpen = hours.isOpen(at: referenceNow)
        return Text(isOpen ? "Open now" : "Closed now")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isOpen ? BrewDeskPalette.moss : BrewDeskPalette.berry)
            )
            .accessibilityIdentifier("hours-open-badge")
    }

    private func dayGroupRow(_ group: OpeningHours.DayGroup) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayGroupLabel(group))
                    .font(.subheadline)
                Spacer()
                dayGroupTimes(group)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(dayGroupLabel(group))
                    .font(.subheadline)
                dayGroupTimes(group)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func dayGroupTimes(_ group: OpeningHours.DayGroup) -> some View {
        if group.segments.isEmpty {
            Text("Closed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(timesLabel(group.segments))
                .font(.subheadline.bold())
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func websiteRow(_ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            businessRowLabel(
                "Website",
                systemImage: "safari",
                value: url.host() ?? url.absoluteString,
                trailingSymbol: "arrow.up.right"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("business-website")
        .accessibilityHint("Opens the website in Safari")
    }

    private func callRow(_ url: URL, number: String) -> some View {
        Button {
            openURL(url)
        } label: {
            businessRowLabel(
                "Call",
                systemImage: "phone",
                value: number,
                trailingSymbol: "arrow.up.right"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("business-call")
        .accessibilityHint("Calls the venue")
    }

    /// Row chrome shared by website/call: ≥44 pt hit region and an explicit
    /// trailing glyph so the tappable rows read as links (bd#36 hit-area and
    /// affordance lessons).
    private func businessRowLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        value: String,
        trailingSymbol: String
    ) -> some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryColor)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.primaryColor)
            }
            Spacer(minLength: 0)
            Image(systemName: trailingSymbol)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// http(s) only — anything else is treated as absent rather than rendered
    /// as a dead row.
    private var websiteURL: URL? {
        guard let raw = venue.website,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private var phoneURL: URL? {
        guard let raw = venue.phone else { return nil }
        let dialable = raw.filter { $0.isNumber || $0 == "+" }
        guard dialable.count >= 7 else { return nil }
        return URL(string: "tel:\(dialable)")
    }


    /// "Mon–Fri" / "Sat" — locale display via OpeningHoursFormatter (bd#56).
    private func dayGroupLabel(_ group: OpeningHours.DayGroup) -> String {
        OpeningHoursFormatter.dayGroupLabel(group)
    }

    /// "7:30 AM – 5:00 PM" in the device locale (24h locales stay 24h);
    /// segments joined with ", ". See OpeningHoursFormatter (bd#56).
    private func timesLabel(_ segments: [OpeningHours.Segment]) -> String {
        OpeningHoursFormatter.timesLabel(segments)
    }

    /// The clock the open-now badge is judged against. UI tests pin it with
    /// `-brewdesk.uitest-fixed-now yyyy-MM-dd'T'HH:mm` (local wall time, via
    /// `LaunchEnvironment.fixedNow`) so open/closed assertions are
    /// deterministic; inert in normal launches.
    private var referenceNow: Date {
        launchEnvironment.fixedNow ?? Date()
    }

    /// `subtitle` is the Workability card's one-time provenance stamp
    /// (brewdesk#119) — nil for every other card, which keeps their own
    /// title row unchanged.
    private func informationCard<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(theme.primaryColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("workability-provenance-stamp")
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrewDeskPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var actionDock: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(spacing: 8) { actionButtons }
        }
        .padding(10)
        .brewDeskGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("action-dock")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            openDirections()
        } label: {
            actionLabel("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        }
        .accessibilityHint("Opens walking directions in Apple Maps")

        Button {
            let wasSaved = savedVenues.contains(venue.id)
            savedVenues.toggle(venue.id)
            // Only a save (not an un-save) counts toward the rating prompt
            // (#160), and never under any UI-test automation — including a
            // real, non-scenario functional run like
            // `testSaveCafeFromDetails`, so `isUITestRun` rather than the
            // narrower `scenario == nil` seam `openDirections()` uses above.
            if !wasSaved, !launchEnvironment.isUITestRun,
                ReviewPromptPolicy().recordSaveAndShouldPrompt() {
                requestReview()
            }
        } label: {
            actionLabel(
                savedVenues.contains(venue.id) ? "saved_action_title" : "save_action_title",
                systemImage: savedVenues.contains(venue.id) ? "bookmark.fill" : "bookmark"
            )
        }
        .accessibilityValue(savedVenues.contains(venue.id) ? "Saved" : "Not saved")
        .sensoryFeedback(.selection, trigger: savedVenues.contains(venue.id))

        ShareLink(item: shareText) {
            actionLabel("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body.bold())
            Text(title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
        }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 8)
            .foregroundStyle(theme.primaryColor)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
    }

    private var shareText: String {
        // Never share the neutral fallback number as if it were a rating
        // (#159), and honor the server's explicit `scoreDisplay` (#213)
        // over the `isObserved` heuristic.
        if let score = venue.displayScore {
            return "\(venue.name) · Work Fit \(score) · \(venue.neighborhood)"
        }
        return "\(venue.name) · not rated yet · \(venue.neighborhood)"
    }

    private func openDirections() {
        // `-UITestScenario` launches never hand off to Apple Maps: doing so
        // backgrounds the app under XCUITest automation, which is flaky at
        // best (a location-permission alert, a slow app switch) and fatal
        // at worst (observed: the test runner treats the app switch as an
        // unexpected exit and restarts). Every other UI-test-only branch in
        // this screen follows the same convention (`-UITestNoPhotos`, etc.).
        // The reminder hook below still fires — this only skips the actual
        // hand-off to Maps.
        guard launchEnvironment.scenario == nil else { return }
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
        )
        let item = MKMapItem(placemark: placemark)
        item.name = venue.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

/// The hero name's bottom edge (`maxY`) in the scroll view's own coordinate
/// space (bd#197). `.infinity` default so a not-yet-measured first frame
/// reads as "still fully on screen" — never a spurious nav-title flash
/// before the GeometryReader lands its first value.
private struct HeroNameFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The launch's `LaunchEnvironment` (bd#101), injected once at `RootView`
/// and read wherever a view needs a UI-test seam. Defaults to `.production`
/// (every flag off) so a view rendered outside that tree — a preview, a
/// package test — behaves like a normal launch.
private struct LaunchEnvironmentKey: EnvironmentKey {
    static let defaultValue = LaunchEnvironment.production
}

extension EnvironmentValues {
    public var launchEnvironment: LaunchEnvironment {
        get { self[LaunchEnvironmentKey.self] }
        set { self[LaunchEnvironmentKey.self] = newValue }
    }
}
