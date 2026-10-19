# Native validation record and device checks

**2026-10-19 update:** the owner requested a website instead. Use the [web app](https://fantasyglass.computerman0.chatgpt.site) and [web source instructions](../Web/README.md). This document retains the native build history.

Recorded **2026-10-18**. The app requires **iOS 26+**. A successful Xcode archive proves compilation and packaging, not successful installation or correct behavior in LiveContainer.

## Current scope

**Version 1.0.1, build 3 removes Dynamic Island, ActivityKit, Live Activities, the widget target and Live Activity backend pushes at the owner's request.** The five native tabs, league imports, local scoring, player tracking, persistence and optional ordinary notifications remain. LiveContainer mode skips background-task registration and notification services. It detects the host's public source-code environment markers (`LC_HOME_PATH` / `LP_HOME_PATH`) without private Apple APIs.

The owner reported that the original 1.0.0 IPA crashes when opened with LiveContainer. No device crash report, iOS version or LiveContainer version has been provided yet. The cause is **not confirmed**; removing Live Activities must not be described as a verified device fix.

## Executed checks

| Check | Result / evidence |
|---|---|
| Portable Swift core on Linux | **19 tests passed**, including the opt-in historical public ESPN requests; [record](validation/swift-core.txt) |
| Original backend suite with public requests enabled | **18 passed**, none skipped; [record](validation/backend.txt) |
| Backend after removing Live Activity support | TypeScript compilation passed; **17 tests passed**, one opt-in network test skipped |
| Shared scoring contract | Swift and TypeScript pass the same **10 cases**, covering decimal scoring and independent league rules |
| Real public fantasy adapter requests | Historical public ESPN league **48153503 / 2019**, 14 teams; this does not prove current/private access |
| Real scoreboard requests | ESPN **2025 week 6**, 15 completed games |
| Original native archive | Xcode **26.3 (17C529)**, iOS SDK **26.2**, unsigned arm64 archive and IPA upload succeeded for 1.0.0; historical evidence, not the replacement build |
| Replacement native archive and IPA | **1.0.1 / build 3 archive succeeded** with Xcode 26.3 / iOS SDK 26.2; no widget target. [Run 39153832071](https://github.com/computerman0/FantasyGlass/actions/runs/39153832071), [evidence](validation/github-build.txt) |
| Simulator launch / SwiftData checks | [Verify 39154409281](https://github.com/computerman0/FantasyGlass/actions/runs/39154409281) failed in the iOS runtime job. No simulator runtime pass is asserted. Work switched to the website at the owner’s request. |

The scoring tests cover standard/half/full PPR, custom and position-specific rules, negative/fractional scores, kicking/defense, bonuses, corrections, decimal capacity, incomplete data and multi-week fallback. Adapter tests cover imports, authentication errors, retries, cooldowns and raw-stat coverage. Backend tests cover authorization, encrypted persistence, notification deduplication, alert-token rotation, JWT signing, configuration changes and outage retention.

An earlier console-attached launch check exited with status 0 and no crash exception. That harness could not distinguish the console command ending from the app process ending; it is not evidence that the device crash was reproduced. A subsequent harness run failed because the simulator launch command exited with status 148 before an app PID was captured. The current script uses explicit `--stdout=...` / `--stderr=...` options, preserves command errors and monitors the actual app PID; neither earlier failure establishes the cause of the reported device crash. First-launch setup now creates Application Support before opening SwiftData, retaining the existing database location.

CI explicitly boots the iPhone simulator before tests. `Scripts/test-ios.sh` builds the app and tests, checks normal and container-mode cold launches, then runs the three SwiftData/deep-link XCTest methods. `Scripts/smoke-ios.py` checks that each launch stays alive for 12 seconds and captures a screenshot. Setting an environment marker in a simulator exercises the fallback; **it does not reproduce LiveContainer's actual app loader**. Launch logs, screenshots and available XCTest results are uploaded as `FantasyGlass-simulator-diagnostics`.

## Still unverified

* Physical-device signing, installation, launch and LiveContainer compatibility. No Apple signing identity or physical iPhone is available in this workspace. An unsigned IPA cannot run as a standalone app without compatible signing.
* VoiceOver, Dynamic Type, appearance, Keychain operations, real background refresh and device notifications.
* Current/private ESPN leagues: no user league ID or private cookies were supplied. Historical public access does not prove current availability or game-day latency.
* SportsDataIO production access, licensing entitlement and live-stat accuracy. Fixtures pass; trial responses may be scrambled.
* Actual APNs delivery, hosted backend deployment, Codemagic signing and TestFlight upload. JWT construction is tested; delivery needs real provisioning and device tokens.
* AltStore/Sideloadly signing and installation. LiveContainer has different capabilities from an independently installed app; [its documented limitations](https://github.com/LiveContainer/LiveContainer#limitations) include unsupported guest extensions and remote pushes.

## Finish validation on your iPhone

1. Use the newest successful **1.0.1 / build 3 or newer** artifact, following [ONLINE_BUILD.md](ONLINE_BUILD.md). Confirm iOS is 26 or newer. Replace the older IPA while preserving its data container when the installation method permits.
2. Verify the setup screen and all five tabs open. If it crashes, retain the crash report and the exact iOS/LiveContainer versions; do not assume a compile success resolved it.
3. Enter league IDs/seasons in the app. Enter private cookies only in the app's secure fields. **Do not send passwords, cookies, API keys, signing keys or backend owner tokens in chat.** Compare team selection, rosters and official totals with ESPN.
4. Inspect a player's category breakdown in each league. Edit a local rule, confirm the local score changes while ESPN settings remain unchanged, and restore the imported rules.
5. Refresh, enable Airplane Mode, relaunch and navigate cached data. Confirm timestamps/stale indicators, expired-credential errors and recovery.
6. For optional SportsDataIO, confirm your licensed production product, test the key on-device, map player IDs explicitly and compare raw statistics.
7. For optional notifications in an independently installed Push build, configure APNs and the HTTPS backend, grant notification permission and test real delivery, deduplication, token rotation and outage recovery. LiveContainer mode disables these services.

There is no calibrated win-probability model. Multi-week playoff totals use official ESPN aggregates. Unknown/reverse/team-bonus rules require review. History/photos depend on provider payloads; Yahoo, Sleeper and Sportradar remain extension points. Foundation Decimal has finite capacity: unsupported precision is rejected and arithmetic capacity failures suppress an asserted local team total. Scores are not silently formatted to two decimal places.
