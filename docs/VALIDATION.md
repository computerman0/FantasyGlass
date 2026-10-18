# Validation record and remaining device work

Recorded **2026-10-18**, on Debian 13 x86_64, using official Swift **6.2** and Node **24.19.0**. These are executed checks, not a claim that an iPhone release has passed acceptance testing.

## Executed successfully

| Check | Result | Evidence |
|---|---|---|
| Portable Swift package, public network smoke test enabled | **19 tests passed**, including three parameterized reception formats | [Swift output](validation/swift-core.txt) |
| TypeScript strict compilation and Node tests, network test enabled | **18 tests passed**, none skipped | [Backend output](validation/backend.txt) |
| Shared scoring contract | Both implementations passed the same **10 cases** | `Core/Tests/FantasyCoreTests/Fixtures/scoring-contract.json` |
| Actual ESPN fantasy adapter requests, Swift and TypeScript | Public league **48153503, season 2019**, 14 teams, rules and roster/schedule data | Opt-in tests in both logs |
| Actual weekly ESPN scoreboard requests, Swift and TypeScript | **2025 week 6**, 15 completed games | Opt-in tests in both logs |
| Deterministic Xcode project | Identical regenerated project/schemes; 106 project objects parsed; all file references exist | [Source checks](validation/project-source.txt) |
| Plists, schemes and Apple-framework source | Eight property lists/entitlements/privacy files, two XML schemes and 18 Swift files syntax-parsed | [Source checks](validation/project-source.txt) |
| Build scripts | Bash syntax checks passed | [Source checks](validation/project-source.txt) |

The Swift suite uses Swift Testing. Its output also contains an empty XCTest compatibility suite; the final Swift Testing line is the **19-test** result. Synthetic fixtures are explicitly test/preview data and are not displayed as live data by the installed app.

Coverage includes standard/half/full PPR, custom and position-specific rates, negative/fractional scores, kicking/defense, bonuses, corrections, independent league rules, decimal capacity, imported rules versus overrides, incomplete data, multi-week fallback, authentication errors, cookies, retries/rate limits, scoreboard decoding, notification transitions and provider coverage. Backend tests also exercise authenticated HTTP, encrypted persistence, cache retention, deduplication, configuration changes, token rotation, APNs payloads and ES256 signatures.

A final Swift live run initially crashed during teardown of a short-lived FoundationNetworking/libcurl session. The default transport now reuses a persistent URLSession with cookie/credential stores disabled. The subsequent full live-enabled run passed; its retained log is linked above. This does not establish Apple-platform behavior.

## Not executed or not proven

* **Xcode compilation, linking, assets, extension embedding and signing:** no macOS, Xcode or Apple SDK was available. Syntax parsing cannot find SwiftUI type/API errors. An actual Xcode build is required before an IPA can be considered usable.
* **Simulator/device checks:** the three SwiftData/deep-link XCTest methods in `AppTests` have not run. Neither have previews, VoiceOver/Dynamic Type checks, Dynamic Island layouts, Keychain operations, background scheduling or device notifications.
* **Current/private ESPN leagues:** no user league ID or private session credentials were supplied. Historical public access does not prove current/private access or game-day latency. Tested 2026 example IDs returned 404. No official ESPN OAuth or discovery integration is claimed.
* **SportsDataIO:** fixture-tested adapter; no account key, production subscription or live-stat accuracy tested. A successful trial response may still be scrambled. Registration/docs links were checked, not account entitlements.
* **APNs/deployment:** JWT and payload construction tested; no Apple key, provisioned iPhone token, remote delivery or hosted deployment available. No backend was published.
* **IPA/sideloading:** no signed or unsigned IPA built. AltStore/Sideloadly installation and widget preservation are untested. An unsigned package is not installable without compatible signing.
* **CI:** the workflow is included but was not run on GitHub here.
* **Online installation:** `build-ipa.yml` and `codemagic.yaml` are supplied with a browser-based guide. Codemagic schema validation and embedded script syntax checks passed ([record](validation/online-workflows.txt)). Their cloud builds, certificate setup and TestFlight upload have not been executed; they do not change the Xcode/device validation boundary above.

## Acceptance status

| Requested outcome | Implementation / remaining blocker |
|---|---|
| Install on an iPhone | Xcode project, assets, extension, entitlements and export scripts; blocked on Xcode build and signing |
| Connect ESPN leagues | Public/private adapter, Keychain entry, connection test and team selection; historical public access verified, your leagues need testing |
| View every fantasy team | Native dashboard and multiple team connections; device validation pending |
| Track players across leagues | Unified grouping, per-league scores, filters, sorting and details; device validation pending |
| Accurate league-specific scores | Portable scoring and cross-language cases pass; actual league discrepancies and unfamiliar rules need review |
| Live player statistics | ESPN raw-stat polling and optional mapped SportsDataIO; current game-day data and paid entitlement unverified |
| Edit local scoring | Separate persisted local overrides and rule editor; SwiftData tests require Xcode |
| Pin a matchup | ActivityKit requests and Island/Lock Screen views; device validation pending |
| Background updates | Opportunistic local updates plus APNs worker; remote delivery requires provisioning, server and device test |
| Understand APIs/credentials | In-app assistant plus setup, feasibility, build and backend guides |
| Ordinary tracking without ESPN | Read-only rosters, schedules, scores and details implemented; end-to-end acceptance remains blocked on the checks above |

There is no calibrated win-probability model. Multi-week playoff aggregates use official ESPN totals. Unknown stat IDs are preserved but their meaning cannot be inferred; reverse scoring, unsupported formats and team bonuses are flagged. History/photos depend on provider payloads. Yahoo, Sleeper and Sportradar are extension points. Foundation Decimal has finite capacity (roughly 38 significant digits): unsupported user-entered precision is rejected, and calculation/aggregation capacity failures suppress an asserted local team total. Scores are not formatted down to two decimal places.

## Finish on your Mac and iPhone

1. Follow [BUILD.md](BUILD.md), select stable Xcode 26+, configure unique bundle IDs and your signing team, and build the local scheme. Resolve any Apple SDK errors before exporting.
2. Run `bash Scripts/test-ios.sh 'platform=iOS Simulator,id=YOUR_UDID'`. Inspect its `.xcresult`, light/dark appearance, accessibility sizes, long names, negative/precise scores and all tabs.
3. Enter your league ID/season in the app. Obtain any required private ESPN cookies locally and enter the secure fields. **Do not send passwords, cookies, API keys, signing keys or owner tokens in chat.** Connect multiple leagues/teams and compare rosters and official totals with ESPN.
4. Check one player's complete breakdown in each league. Edit a local rate, confirm the local score changes and ESPN settings remain unchanged, then restore imported rules. Check a genuine stat correction when available.
5. Refresh, enable Airplane Mode, relaunch and navigate cached data. Confirm timestamps and stale indicators remain honest. Test expired credentials and recovery.
6. On a compatible iPhone, pin/switch/end matchups. Check compact, expanded and Lock Screen views, stale presentation, default selection and exact-matchup deep links. Local-only updates may stop while suspended.
7. For optional SportsDataIO, register using the official link, confirm your licensed production product, save the key on-device, test access and explicitly map player IDs. Compare raw statistics before relying on the feed.
8. For optional remote updates, follow the backend and Push signing guides. Provision APNs, deploy HTTPS, consent to server storage and re-pin. Verify background timestamp changes, actual alert transitions, deduplication, token rotation and stale presentation after an outage.
9. Export after these checks pass. Test your selected sideloading method and confirm the widget and required entitlements survive signing.

A Mac with Xcode, signing identity and your league details are needed to finish installation validation. SportsDataIO and an APNs server are optional; the on-device ESPN path does not require them.
