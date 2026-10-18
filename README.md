# FantasyGlass

A native Swift 6 / SwiftUI fantasy football tracker for **iOS 26+**, with a WidgetKit Live Activity extension, SwiftData caching, an exact-decimal scoring engine, ESPN provider adapter, optional SportsDataIO statistics, and an optional TypeScript APNs backend. This is an Xcode application, not a website.

**Build status:** the portable Swift core and backend are tested on Linux, including real historical public ESPN requests. The Apple-framework source passes syntax parsing, but **Xcode compilation, simulator tests, signing, device behavior, private/current-season ESPN access, SportsDataIO subscriptions and APNs delivery are not validated here**. No IPA was fabricated. A macOS host with stable Xcode 26+ is needed for compilation; it can be a cloud build service. Physical-device validation still requires your iPhone.

## Start here

**No Mac?** Follow the [online build and iPhone installation guide](docs/ONLINE_BUILD.md). It includes GitHub Actions IPA export and a Codemagic/TestFlight route with browser-based signing setup.

1. Read the [verified feasibility report](docs/FEASIBILITY.md), especially unofficial ESPN access and Apple's background/signing restrictions.
2. Follow [build and installation](docs/BUILD.md) to open `FantasyGlass.xcodeproj`, choose your signing team, and install or export an IPA.
3. Use the app's setup assistant or [API setup guide](docs/SETUP.md). Public ESPN leagues need only an ID, season and selected team. Private cookies and optional API keys go into **Keychain on your iPhone**, never into source or chat.
4. For remote updates, follow [backend deployment](Backend/README.md). On-device tracking works without the backend; background delivery needs real APNs provisioning.
5. See [validation and remaining limitations](docs/VALIDATION.md) before relying on game-day scores.

## Included

* Five native tabs: Dashboard, Players, Matchups, Leagues and Settings. Native iOS 26 tab/navigation materials and Liquid Glass controls, light/dark appearance, Dynamic Type, SF Symbols and accessibility labels.
* Multiple ESPN leagues and multiple followed teams per league/account. Team selection, rosters, current matchups, standings, schedule, projections and history when present in the provider response. No write API changes ESPN settings.
* A unified player list with expandable per-league scores; player/game/league/status/starter/bench filters and points, projection, time or name sorting. Opponent roster details are available from matchups.
* Decimal scoring, imported position-specific rules, local overrides, linear/threshold/range/whole-unit rules, kicker and defense categories, IDP statistics, negative values, corrections and category-by-category explanations. Official ESPN totals remain available for discrepancy comparison.
* Secure ESPN account aliases and cookies, optional SportsDataIO setup and connection tests, explicit player-ID mapping and field-coverage checks. Provider errors, cooldowns, timestamps and cached navigation.
* ActivityKit tracking, compact/expanded Dynamic Island and Lock Screen layouts, activity switching/ending, defaults, deep links, stale dates and push-token rotation. Local and APNs-enabled build schemes are separate.
* Configurable foreground/opportunistic notifications, plus a server worker for background event detection and APNs alerts. Encrypted SQLite subscription storage, stable event IDs, a persistent delivery queue, retry handling and authenticated HTTPS deployment templates.
* Swift/package tests, HTTP/adapter fixtures, cross-language scoring cases, SwiftData tests for Xcode, preview-only sample data, app icon, entitlements, configuration templates, deterministic project generator, CI and IPA scripts.

## Source layout

| Path | Purpose |
|---|---|
| `App/` | Native SwiftUI screens, observable view model, SwiftData/Keychain/notification services |
| `Core/` | Dependency-free Swift package: models, scoring, HTTP, providers, event detection and tests |
| `Shared/` | Activity attributes and exact-matchup deep links compiled into app and extension |
| `Widget/` | Lock Screen and Dynamic Island Live Activity UI |
| `AppTests/` | SwiftData and deep-link tests requiring Xcode |
| `Backend/` | Optional Node 24 + TypeScript/SQLite/APNs server and tests |
| `Config/` | Info plists, signing templates and entitlements |
| `Scripts/` | Reproducible project generation, tests and IPA builds |
| `docs/` | Research, architecture, setup, build and validation guidance |

## Run portable checks

```sh
swift test --package-path Core
cd Backend
npm ci --ignore-scripts
npm test
```

Opt-in public network checks (no credentials required):

```sh
FANTASYGLASS_LIVE_SMOKE=1 swift test --package-path Core
cd Backend
FANTASYGLASS_LIVE_SMOKE=1 npm test
```

If your environment requires an HTTP proxy, retain its proxy/CA settings; Node 24 can use `NODE_USE_ENV_PROXY=1`. APNs uses outbound HTTP/2 TLS and must be reachable from the deployed backend.

## Material limits

There is no validated ESPN OAuth/account-wide discovery integration. There is no calibrated win-probability model. Multi-week matchup aggregates fall back to official ESPN scores because a current roster cannot recreate prior-week lineups. Unknown/reverse/team-bonus rules require review; arbitrary formulas cannot be inferred from missing raw data. History and photos depend on what the provider actually supplies. Sportradar, Sleeper and Yahoo adapters are extension points, not claimed working integrations.

Free Apple ID signing and arbitrary re-signing services do not imply APNs support. A local-only Live Activity can become stale while the app is suspended, and an active Live Activity is limited to eight hours. Paid feeds, provider terms, Apple membership and always-on hosting may impose costs. See the linked documentation for the exact boundaries.

ESPN, NFL and provider trademarks belong to their owners. This project is not affiliated with them and grants no sports-data or image redistribution license. See [third-party notices](THIRD_PARTY_NOTICES.md).
