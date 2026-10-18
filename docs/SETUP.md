# API and account setup

The app includes these instructions and connection-test controls. The only mandatory provider for the initial app is ESPN. SportsDataIO, a backend and paid Apple provisioning are optional unless you need those particular capabilities.

## ESPN: public leagues

1. Open your league at [ESPN Fantasy Football](https://www.espn.com/fantasy/football/). The browser URL contains `leagueId=...`. Determine its season year.
2. In FantasyGlass, choose **Leagues → +** or the setup assistant. Enter the numeric league ID and season, then **Test Connection**.
3. After the request succeeds, inspect the returned league name and select every team you own. Save the selection. You can connect more leagues and different ESPN account aliases.
4. Pull to refresh. During active NFL games the foreground app defaults to one refresh per minute; rate limits can lengthen that interval. Successful retrieval does not guarantee ESPN has updated its upstream data.

The tested public examples are league `1234` / `2018` and `48153503` / `2019`. They are **historical integration checks**, not your teams or current live demonstrations. Later-season probes for those IDs returned 404. Manual league entry is the supported app workflow; no official account-wide league discovery is claimed.

## ESPN: private leagues

There is no official ESPN OAuth integration here. The adapter uses existing, user-supplied session cookies. This is unofficial, may stop working, and may be restricted by ESPN's terms. The app never asks for your ESPN password.

1. Sign in to ESPN yourself in a browser you control. Open Developer Tools → Application/Storage → Cookies for the ESPN domain. Safari/Firefox/Chrome labels differ.
2. Locate your own `espn_s2` and `SWID` cookie values. Preserve their values as displayed, including SWID braces when present. Don't include `Cookie:`, field names, semicolons or line breaks. Don't copy someone else's session.
3. Enter them in the app's **Settings → ESPN account** secure fields, assign an account alias, and save to Keychain. The two values are stored atomically as a single Keychain item with `AfterFirstUnlockThisDeviceOnly` accessibility so permitted background work can use them after first unlock.
4. Return to **Connect ESPN**, select that alias, enter a league you can access and run **Test Connection**. ESPN access is verified per league; merely saving cookies does not verify authentication.
5. If access later fails, re-enter a fresh session. HTTP 401/403 and private-league 404 responses are explained in the app. Cached data remains visible with its original timestamp.

Treat cookies like bearer credentials that can grant account access. Do not paste them into chat, commit them, put them in a URL, or send screenshots containing them. No password-login automation, browser cookie extraction or account bypass is included. The app's requests are read-only. Cookie/API-key headers do not follow HTTP redirects. Device deletion removes the Keychain record; when remote mode is active the next successful synchronization also removes the server's copy. If synchronization fails, disable/remove the server subscription directly before considering the server copy gone.

## Optional SportsDataIO statistics

Verified official links:

* [Register / trial](https://sportsdata.io/cart/free-trial)
* [NFL endpoints](https://sportsdata.io/developers/api-documentation/nfl)
* [NFL data dictionary, including scrambled-data flags](https://sportsdata.io/developers/data-dictionary/nfl)

Register, request **NFL player game statistics**, and ask the vendor to confirm live access, history, permitted use, polling frequency, quotas and price for your account. An HTTP-successful trial may return scrambled values; the data dictionary flags many statistics as scrambled. Do not use a trial as proof of score accuracy. No production price or guaranteed free real-time tier was verified.

Copy your API key from your provider account into **Settings → Sports data providers**, save it in Keychain and run **Test Connection**. This calls `PlayerGameStatsByWeek/{season}REG/{week}` with `Ocp-Apim-Subscription-Key`. It validates HTTP access and response structure, not the commercial entitlement or numerical truth of trial values. Quota is shown as unavailable because this response does not expose a reliable allowance.

Select SportsDataIO and confirm that your plan provides accurate licensed production statistics. On each Player page, enter the exact SportsDataIO `PlayerID` for that ESPN player. The connection-test screen lists IDs returned by the API for reference. Identity is never guessed from a similar name. Mappings are global across your leagues.

The adapter replaces a player's raw stat line only when it has every nonzero category needed by that league/position. It does not merge ambiguous partial lines. Missing categories retain ESPN data and produce a coverage note. D/ST-specific or unusual derived rules often require fields outside this player endpoint and therefore remain on ESPN. Optional projections remain those supplied with ESPN's fantasy payload; a paid projection endpoint is not falsely claimed connected. Switch providers in Settings without rebuilding.

Sportradar's [NFL documentation](https://developer.sportradar.com/football/docs/nfl-ig-api-basics) was reviewed. Its current guide says API keys belong on a server. A Sportradar adapter, Sleeper adapter or Yahoo OAuth integration is not included; the provider interfaces support future additions.

## Optional APNs backend

The app's **Settings → APNs and backend** screen walks through provisioning, HTTPS, the owner token, a connection test and explicit consent for encrypted server credential storage. See `BUILD.md` and `../Backend/README.md` for exact deployment steps.

Do not enter the Apple `.p8` signing key in the app. It belongs on your server. The app stores only its backend owner token in Keychain and sends subscriptions over HTTPS after you enable remote mode. With remote mode off, it does not upload your ESPN cookies or API keys.

Server access testing does not prove APNs delivery. Install the Push build with matching profiles, configure sandbox/production correctly, grant alert permission, re-pin the matchup and perform an actual device test. A sideloading method that strips APNs entitlements or changes the signing identity cannot provide this delivery path.

## Scoring and discrepancies

Open **Leagues → your league → Inspect and edit local scoring**. Imported ESPN rules remain read-only; saving creates a separate local configuration. Presets and custom rules support decimal multipliers, position overrides, thresholds, inclusive ranges and whole-unit buckets. Raw numeric ESPN categories are retained, including uncommon ones. Existing ESPN bucket categories already encode many distance/yardage bonuses; adding another equivalent bonus can intentionally double-count them.

Scoring supports Decimal's finite precision (approximately 38 significant digits). Capacity errors are surfaced, not silently accepted as accurate. Whole-unit rules deliberately truncate toward zero; other multiplication/addition does not round to a display precision. Both the local result and ESPN's official value are available. Imported reverse-scoring/team-bonus/nonstandard-format warnings require review before a complete local total is asserted.

Multi-week playoff aggregates use ESPN's official matchup totals. Player explanations remain weekly; historical lineup reconstruction is not implemented. Missing raw statistics produce an unavailable local score. A team can still show its official ESPN score with the source clearly labeled. No arbitrary win probability is generated.

## Notifications and offline use

Enable individual alert types in Settings and allow notifications in iOS. Set a player's point threshold on the Player page. Thresholds are evaluated independently under each followed league's scoring rules. The initial observation establishes a baseline and does not generate historical alerts. Rule/source edits reset baselines to avoid falsely presenting a configuration change as a touchdown or stat correction.

Without the backend, detection runs only during foreground refresh or background time granted by iOS. With the backend, polling and persistent event IDs drive APNs alerts. Polling can miss brief halftime/injury states, and aggregate touchdown counters cannot distinguish every correction from a new play. Notification delivery is not exactly-once guaranteed by APNs; persistent deduplication and collapse IDs reduce duplicates.

SwiftData preserves league snapshots, rules, games and alert state offline. Reopen the app without a network to browse the last cache. Timestamps say when FantasyGlass retrieved data; they do not invent a provider publication time. Delayed score/game states are labeled. Failed refreshes do not replace cached data with zeros.
