# FantasyGlass Web

A private, responsive fantasy football dashboard for Safari and desktop browsers. Connect multiple ESPN teams, combine players across leagues, inspect exact scoring, and save local rule overrides. Add the website to your iPhone Home Screen from Safari's Share menu; no Xcode, IPA, signing certificate, or LiveContainer is required.

## What works

- Public ESPN league lookup by ID/link and season; private lookup with user-provided `espn_s2` and `SWID` cookies. Select multiple owned teams from the same league.
- Matchups, official scores, locally calculated scores, projections when supplied, rosters, standings, schedules, raw stats, and weekly history returned by ESPN.
- Player grouping across leagues, search, league/game/status/starter/bench filters, four sort modes, pinned players, and exact per-league breakdowns.
- Exact base-10 scoring, imported rules kept separately from overrides, linear/threshold/range/whole-unit rules, position rates, and an editable scoring screen.
- Persistent account-scoped league snapshots in D1. AES-256-GCM encrypted ESPN cookies with user/league authenticated context. No cookies are returned to the browser after saving or placed in source, logs, browser storage, or URLs.
- Adaptive foreground refresh, HTTP cooldowns/retries, bounded provider responses, last-update timestamps, stale-data indicators, and a browser snapshot for reconnect/offline use in the same session.
- Private hosted authentication supplied by Sites, same-origin mutation checks, request quotas, allowlisted upstream endpoints, responsive navigation, keyboard-accessible dialogs, light/dark mode, and reduced-motion support.

The sample dashboard is explicitly labeled and never saved as live league data.

## Connect your league

1. Open the private site and sign in with the owning ChatGPT account.
2. Select **Connect league**. Enter an ESPN league ID or league URL and the season.
3. Public leagues need no API key. For a private league, enable **This is a private league**, then enter your own `espn_s2` and `SWID` cookies in the secure fields.
4. Select **Test connection**, choose your team(s), and import them.
5. Inspect a player or open **Leagues → Scoring rules**. Local edits never write to ESPN.

ESPN provides no supported public fantasy API/OAuth flow for this integration. Session cookies act as credentials, can expire, and may be obtained from your own signed-in desktop browser's cookie inspector. Do not share them in chat or commit them to GitHub. iPhone Safari does not expose a normal cookie inspector; private-league setup may require a desktop browser once. Cookie and current-season access cannot be verified without your credentials/league.

## Development

Node.js 24+:

```sh
npm ci
npm run build
npm run typecheck
npm test
npm run dev
```

Open `http://127.0.0.1:5173`. The development server injects a loopback-only test identity; this is not compiled into the hosted worker. The local database is ignored under `.local/`. Use an untracked `FANTASYGLASS_ENCRYPTION_KEY` environment value (64 random hex characters) if local private-cookie storage must survive server restarts; otherwise development uses an ephemeral key.

If your execution environment requires a proxy, preserve it; Node 24 can use `NODE_USE_ENV_PROXY=1`. Production Worker fetches use the hosting network directly.

```sh
FANTASYGLASS_LIVE_TESTS=1 npm test
npx playwright install chromium
npx playwright test test/browser.spec.mjs --workers=1
# Optional, while the local server runs, imports and removes a historical public league:
npx playwright test test/browser-live.spec.mjs --workers=1
```

`test/fixtures` contains synthetic adapter/scoring fixtures and a historical scoreboard. The shared scoring contract originated in the native Swift/backend project. Tests cover precision, scoring modes, authenticated encryption, ownership, CSRF, provider caching/rate limits, imports, overrides, and deletion.

## Hosting

The app builds to a single standard Worker ES module at `dist/server/index.js`, with its static assets embedded. `.openai/hosting.json` records the Site ID and logical D1 binding. Drizzle owns the schema and generated migrations; never mutate applied migration history. The hosting platform provisions D1 and applies migrations during deployment.

Configure `FANTASYGLASS_ENCRYPTION_KEY` as a **secret runtime variable**, not a source file. Deployments use the existing private Site and exact pushed source commit. Keep the audience private. Hosted authentication injects `oai-authenticated-user-id`; every data endpoint requires and scopes queries to that identity. Do not expose this worker behind an untrusted proxy that lets clients forge identity headers.

The local Sites scaffold/source helper executables were unavailable in this workspace. The web build uses a conventional React/esbuild Worker artifact compatible with Sites, and source synchronization uses a credential passed only through hidden stdin and process environment. The required authentication and private publishing boundaries are retained.

## Practical limits

- ESPN endpoints are unofficial, have no SLA or published quota, and may restrict access. A successful historical public import does not establish current/private access or game-day latency.
- Refresh runs while the page is open. iOS may suspend browser tabs or installed web apps. Reliable background notifications, Dynamic Island, and APNs are not implemented in this web version.
- A refreshed projection is a provider estimate; win probability is not fabricated. Unsupported rules and multi-week aggregates fall back to official scores. History is shown only when returned.
- SportsDataIO, Yahoo, and Sleeper are not connected in the web version. No paid feed is required for the ESPN starting configuration.
- Offline snapshots are device/session-local. Server records persist across signed-in sessions. Private login must first succeed online.
- Source code is mirrored in the owner's public GitHub repository; personal league records and credentials are not.
