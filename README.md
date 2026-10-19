# FantasyGlass

**Web app:** [Open FantasyGlass](https://fantasyglass.computerman0.chatgpt.site)

FantasyGlass is now available as a private website. Open it in Safari, sign in with your owning ChatGPT account, and select **Connect league**. To keep it on your iPhone, use **Share → Add to Home Screen**. No Mac, IPA, signing certificate, or LiveContainer is needed.

The web dashboard supports multiple ESPN teams, unified player tracking, matchup scores, exact scoring breakdowns, editable local rules, encrypted private-league cookies, and saved snapshots. Public ESPN leagues need no paid API key. Private leagues require your own valid `espn_s2` and `SWID` cookies, entered only in the website. ESPN password entry is never requested.

Source and developer instructions: [Web/README.md](Web/README.md). The React/TypeScript app and server are in `Web/`; private league data and credentials are not in GitHub. ESPN access uses unofficial endpoints. Current/private access still requires your league details, and background browser refresh is not guaranteed.

**Validated on 2026-10-19:** web build/typecheck, 10 core/API/security tests including a historical public ESPN request, and three Chromium browser flows including import/reload, desktop/mobile layouts, player details, scoring edits, and error handling. Private deployment succeeded. This does not claim a physical iPhone Safari test or private/current-season ESPN verification.

## Retained native iOS project

The native source remains below for reference. The browser version above is the recommended route after the reported LiveContainer crash.

A native Swift 6 / SwiftUI fantasy football tracker for **iOS 26+**, with SwiftData caching, an exact-decimal scoring engine, ESPN provider adapter, optional SportsDataIO statistics, and an optional TypeScript APNs backend. This is an Xcode application, not a website.

**Current version: 1.0.1 (build 3).** Dynamic Island, Live Activities and the widget extension have been removed. The original IPA compiled but was reported to crash in LiveContainer. [Download the successfully built 1.0.1 IPA](https://github.com/computerman0/FantasyGlass/actions/runs/39153832071) under **Artifacts → FantasyGlass-unsigned-IPA**; do not reuse the old 1.0.0 artifact. The replacement adds a foreground-only LiveContainer path. Its physical-device behavior is not yet confirmed. The IPA still needs compatible signing for installation as an independent iPhone app. See the [validation record](docs/VALIDATION.md).

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
* Matchup deep links and separate local / APNs notification build schemes. Dynamic Island, Live Activities and the widget extension were removed in version 1.0.1 at the owner's request.
* Configurable foreground/opportunistic notifications, plus a server worker for background event detection and APNs alerts. Encrypted SQLite subscription storage, stable event IDs, a persistent delivery queue, retry handling and authenticated HTTPS deployment templates.
* Swift/package tests, HTTP/adapter fixtures, cross-language scoring cases, SwiftData tests for Xcode, preview-only sample data, app icon, entitlements, configuration templates, deterministic project generator, CI and IPA scripts.

## Source layout

| Path | Purpose |
|---|---|
| `App/` | Native SwiftUI screens, observable view model, SwiftData/Keychain/notification services |
| `Core/` | Dependency-free Swift package: models, scoring, HTTP, providers, event detection and tests |
| `Shared/` | Exact-matchup deep links for the app and notifications |
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

Free Apple ID signing and arbitrary re-signing services do not imply APNs support. Foreground polling stops when the app is suspended. LiveContainer mode disables background refresh and notification services. Paid feeds, provider terms, Apple membership and always-on hosting may impose costs. See the linked documentation for the exact boundaries.

ESPN, NFL and provider trademarks belong to their owners. This project is not affiliated with them and grants no sports-data or image redistribution license. See [third-party notices](THIRD_PARTY_NOTICES.md).
