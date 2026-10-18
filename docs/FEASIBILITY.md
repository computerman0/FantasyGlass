# Feasibility and verified research

Research performed 2026-10-18. Direct HTTPS requests and Apple DocC JSON were used because the web-search connector failed. HTTP success establishes reachability, not subscription rights or production guarantees. Machine-readable request results are in `research/verification*.json`.

## Findings

* Native SwiftUI, SwiftData, ActivityKit, WidgetKit, Keychain, UserNotifications and native iOS 26 Liquid Glass are suitable. Apple documents `glassEffect`, `GlassEffectContainer` and `.buttonStyle(.glass)`. Standard tab/navigation components adopt system glass. There is no Xcode or Apple SDK in this Linux environment. Swift 6.2 was installed to compile and test the portable core; iOS compilation must run on macOS with Xcode 26 or newer and its installed stable SDK.
* ESPN has no verified supported public fantasy API or official OAuth integration for this app. The unofficial `lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{id}` endpoint answered HTTP 200 for public leagues **1234 / 2018** (10 teams) and **48153503 / 2019** (14 teams). Views: `mSettings`, `mTeam`, `mRoster`, `mMatchup`, `mMatchupScore`. A 2026 probe and an arbitrary league returned 404. No private credentials were available. Current-season private access is **unverified**. The integration is read-only and isolated in `ESPNProvider`.
* The ESPN NFL scoreboard and game-summary endpoints returned HTTP 200 with real historical data. They are unofficial, have no SLA or published quota, can change or block clients, and confer no redistribution/image license. The default stat source is raw weekly player statistics included in the fantasy payload. Scoreboard data supplies game states. There is no claimed second-by-second SLA. The app retains raw stat IDs, scoring multipliers, position overrides, official totals, schedules and historical stats actually returned.
* Account-wide league discovery is not a verified supported ESPN capability. Manual league ID, season, account alias and team selection are implemented. The same league can be followed for multiple owned teams. Existing ESPN session cookies (`espn_s2`, `SWID`) may enable private access, but are bearer credentials, can expire, and are not official delegated authorization. Never enter an ESPN password. Obtain your own cookies locally after signing in to ESPN in your browser's developer tools; don't share them in chat, logs or source. Keychain entry is on-device. See `SETUP.md`.
* Apple explicitly gives `BGAppRefreshTask` system-controlled timing and up to about 30 seconds of execution. It cannot guarantee game-time updates. Foreground polling and occasional refresh can update an existing Live Activity locally. APNs ActivityKit pushes enable updates while suspended, subject to system delivery/budget limits. APNs credentials, paid program provisioning and a reachable server are needed for the supplied optional backend. Personal Team builds use local updates without the APNs entitlement.
* Apple documents an eight-hour active Live Activity limit, with up to four more hours on the Lock Screen after ending, and a combined 4 KB static/dynamic data limit. A Sunday-through-Monday matchup cannot remain continuously in Dynamic Island. The app permits re-pinning. `staleDate`, token rotation, ending, restored activity observation and exact-matchup deep links are included. Ordinary alert pushes use separate device tokens.
* A normal iPhone will not execute an unsigned IPA. AltStore/Sideloadly re-sign an app; free Personal Team profiles commonly expire after seven days and have app/device limits. APNs is not a Personal Team capability. Re-signing must preserve compatible widget bundle identifiers and entitlements. Remote pushes are not promised for arbitrary sideloading services. See `BUILD.md`.

## Provider comparison

| Source | Player stats / fantasy use | Frequency and history | Cost/authentication | Restrictions / decision |
|---|---|---|---|---|
| ESPN unofficial fantasy + scoreboard | Raw numeric stat categories, league rules, official scores, projections when returned; local calculation | No published SLA; historical seasons tested; game-day polling 60 seconds by default | No API subscription; public or user session cookies | Fragile endpoint, no official API/OAuth/license. Best practical zero-subscription personal starting point; not a licensed commercial feed. |
| SportsDataIO NFL | Documented player game stats, kicking, defense, injury, projections with appropriate products | Endpoint-specific call intervals; live entitlement and historical coverage depend on plan | API key (`Ocp-Apim-Subscription-Key`); production price requires current quote | Data dictionary marks many statistical fields “Scrambled.” A free trial is unsuitable for asserting accurate live scores. Documentation template also contains inconsistent trial wording; verify entitlement with vendor. Optional adapter, explicit production-feed confirmation and exact player-ID mapping. No price fabricated. |
| Sportradar NFL official | Detailed game/player statistics, play-by-play and historical feeds; enough for fantasy with mappings | REST feed cadence and push availability depend on contract | `x-api-key`; trial restrictions and production pricing are account/contract specific | Current docs explicitly say keep key server-side. Strong licensed commercial choice; no turnkey on-device adapter is claimed. Requires backend integration and license. |
| nflverse | Useful historical/open football analysis data | Batch/publication schedule, not a guaranteed live feed | Public datasets; per-dataset licensing | Useful future historical analytics source, not a live-scoring substitute. |
| Sleeper | Supported fantasy league/roster endpoints | Not selected as a licensed NFL raw live statistics source | Public read APIs for relevant fantasy data | Future fantasy-provider adapter; not implemented as a working NFL feed. |

No fixed subscription price, free live tier, guaranteed latency, or commercial redistribution right is assumed. Live-feed subscription validation requires an actual account. The optional SportsDataIO connection tests HTTP access and payload shape, not truthfulness of scrambled trial data. Quota is shown as unavailable when the provider does not return it.

## Sources retrieved successfully

* [ESPN Fantasy Football](https://www.espn.com/fantasy/football/) — onboarding landing page verified HTTP 200; the shorter `fantasy.espn.com/football/` path returned 404 and was replaced.
* [Apple: applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
* [Apple: displaying Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
* [Apple: starting and updating via ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
* [Apple: background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
* [Apple: membership comparison](https://developer.apple.com/support/compare-memberships/)
* [SportsDataIO NFL documentation](https://sportsdata.io/developers/api-documentation/nfl)
* [SportsDataIO NFL dictionary](https://sportsdata.io/developers/data-dictionary/nfl)
* [SportsDataIO registration](https://sportsdata.io/cart/free-trial)
* [Sportradar NFL API basics](https://developer.sportradar.com/football/docs/nfl-ig-api-basics)
* [Community ESPN adapter](https://github.com/cwendt94/espn-api) — corroboration of unofficial request fields, not ESPN support or licensing authorization.

## Boundaries that remain

The exact weekly scoreboard query used by both adapters (`dates=2025&seasontype=2&week=6&limit=100`) returned 15 games through both implementations. This is a historical check, not proof of current live data. Sideloadly's homepage returned 200; AltStore's site returned 403 from this environment, so its installation workflow was not verified here.

Unusual reverse-scoring rules, non-head-to-head formats and home bonuses are flagged for review rather than asserted accurate. Multi-week playoff aggregate scores use official totals because current-week rosters cannot reconstruct historical lineups. Missing raw stats produce an unavailable local score, not a fake zero. A calibrated win-probability model is not available; the UI says unavailable rather than generating a misleading percentage. Photos are displayed only if the selected provider supplies a URL; this does not grant redistribution rights. No external secret or Apple signing identity was available during development.
