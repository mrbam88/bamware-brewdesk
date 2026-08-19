# iOS engineering notes

BrewDesk is both a product and a study project. These notes connect the code to
the iOS concepts behind it, with React Native and Node analogies where useful.

## SwiftUI views

A SwiftUI `View` is a value describing UI for current state, closer to a React
function component than a UIKit view object. SwiftUI recreates these values
often. Persistent state must live in property wrappers or referenced models,
not ordinary stored variables created during `body` evaluation.

In BrewDesk:

- `RootView` owns app-flow state.
- `DiscoveryRootView` owns discovery and Saved models.
- Map, list, and details receive those shared references.

Exercise: trace one filter tap from `CafeMapScreen` to the new network request
and identify which views read the resulting state.

## Observation

`@Observable` lets Swift track which properties a view actually reads. It is
similar to a small Zustand store with compiler-assisted subscriptions.

- `@State` owns an observable reference for a view's lifetime.
- `@Bindable` creates bindings to mutable observable properties.
- `@ObservationIgnored` excludes dependencies and implementation details.

Older SwiftUI commonly used `ObservableObject`, `@Published`, `@StateObject`,
and `@ObservedObject`. Those remain important when supporting older platforms
or integrating Combine-heavy code, but Observation is less ceremonial for an
iOS 17 app.

## Combine refresher

Combine models streams over time.

```text
Publisher -> operators -> Subscriber
```

React/Node analogy: a Publisher resembles an RxJS Observable. Operators such as
`map`, `filter`, `debounce`, `removeDuplicates`, and `combineLatest` transform
events. `AnyCancellable` represents the subscription lifetime.

Key pieces:

- `Just`, `Future`, notifications, timers, and subjects create publishers.
- `sink` subscribes with value/completion closures.
- `assign` writes values to a property.
- `receive(on:)` changes where downstream work is delivered.
- `subscribe(on:)` affects upstream subscription work.
- `PassthroughSubject` emits events without retaining a current value.
- `CurrentValueSubject` retains and emits its current value.
- Store cancellables for as long as the subscription should live.

Why BrewDesk does not currently use Combine:

- UI invalidation is handled by Observation.
- Network requests are one-shot `async` functions.
- Core Location exposes an `AsyncSequence`.
- Search submits explicitly rather than maintaining a debounced stream.

Combine would be reasonable for a genuinely multi-source continuous pipeline,
legacy KVO/notification integration, or an SDK already exposing publishers. Do
not introduce it merely to replace a readable `async` function.

Exercise: sketch search-as-you-type with `debounce` and `removeDuplicates`,
then compare it with cancelling a `Task` that sleeps before submission.

## Structured concurrency

`async/await` expresses one asynchronous operation. `Task` gives that work a
lifetime. Structured child tasks inherit cancellation and priority from their
parent.

`.task(id:)` is similar to an abortable React `useEffect`: when the ID changes,
SwiftUI cancels work tied to the previous identity.

Cancellation is cooperative. Code should reach suspension points or call
`Task.checkCancellation()`. BrewDesk also uses a generation guard because a
mock or future SDK might ignore cancellation.

## MainActor and Sendable

`@MainActor` serializes UI state on the main actor. It does not mean every
awaited network operation blocks the main thread.

`Sendable` states that a value can cross concurrency boundaries safely.
Immutable venue models are Sendable. Mutable UI models stay main-actor isolated.

An actor is useful for shared mutable state that must serialize access. Avoid
creating actors for immutable models or state already owned by the main actor.

## Dependency injection

BrewDesk uses constructor injection at the app edge. Protocols describe narrow
capabilities, and tests provide fakes.

React analogy: this is explicit prop/context injection rather than importing a
global singleton. Express analogy: it resembles passing a service into a route
factory rather than importing a process-wide client in every handler.

The goal is substitution and clear ownership, not maximizing protocol count.

## Codable and API contracts

`Codable` maps JSON into typed values. Coding keys handle API naming differences
such as `distance_m`.

Client types are not proof of the server contract. Compare them with the Venue
Engine schema whenever the response changes, then test a live Release request.

Keep transport values stable and localize only display labels.

## Swift Package Manager

A package product is what another target imports. A package target is the
module compiled from source. BrewDesk's in-repo package exposes two products:

- `BrewDeskKit`: feature UI and state
- `VenueKit`: domain and networking

The app project pins the shared `bamware-ios` revision. The development
workspace substitutes a sibling checkout without committing machine-specific
paths.

## Core Location and MapKit

`LocationService` requests when-in-use permission and consumes the iOS 17 live
update sequence. Permission remains optional; Union Square is the deterministic
fallback.

Map annotations are interactive SwiftUI views. They still require explicit
VoiceOver labels, selected state, minimum targets, and a list alternative.

## Localization and accessibility

Localization is architecture, not translation cleanup. Keep user-facing keys in
catalogs, format measurements with the current locale, and avoid building
sentences from translated fragments.

Accessibility basics used here:

- Semantic Dynamic Type styles
- Scrollable layouts at accessibility sizes
- 44-point controls
- VoiceOver labels, values, hints, and selected traits
- State communicated by more than color
- Reduce Motion support
- Automated accessibility audits plus physical testing

## Testing

Swift Testing (`@Test`, `#expect`) is concise for model and state tests. XCTest
remains the framework for UI automation, attachments, launch configuration,
and accessibility audits.

Tests should prove behavior at the cheapest layer that can observe it. A mocked
decoder test cannot prove the production API or signed archive works.

## Release mental model

```text
source -> tests -> archive -> export/sign -> upload -> process -> TestFlight install
```

Each arrow is a separate gate. A successful upload is not a processed build,
and a processed build is not a physical smoke test.

Read `docs/RELEASING.md` before touching signing or App Store Connect.
