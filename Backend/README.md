# Optional FantasyGlass APNs backend

This server is only needed for independent background polling and push delivery. The native app can operate without it. It is designed for **one owner**, potentially with several devices and many league/team subscriptions. It is not a public multi-tenant SaaS.

Node 24, TypeScript and Node's built-in SQLite/crypto/HTTP2/HTTPS modules are used. There are no runtime npm dependencies. Use a small, always-on VPS, a home server reachable over HTTPS, or another persistent process with durable storage. Sleeping/free serverless hosts are unsuitable for a 60-second poller and SQLite. No free hosting plan or fixed monthly cost is promised. APNs itself does not charge per push, but compatible Apple Developer membership and licensed feed access can cost money.

## Local preparation

```sh
cd Backend
npm ci --ignore-scripts
npm test
npm run build
cp .env.example .env
node scripts/generate-secrets.mjs
```

Run the secret-generation command locally. Put its output into your `.env` or secret manager; don't send it in chat or commit it. The encryption key must be exactly 32 random bytes encoded as base64. The owner token should have at least 256 bits of entropy. Keep `.env` and APNs `.p8` files mode `0600`, outside a public web root.

Set:

| Variable | Value |
|---|---|
| `OWNER_TOKEN` | Long random bearer token; enter this one in the app's Keychain setup |
| `DATA_ENCRYPTION_KEY` | Base64 32-byte AES key, server only |
| `DATABASE_PATH` | Persistent SQLite file, e.g. `/var/lib/fantasyglass/fantasyglass.sqlite` |
| `BIND_HOST` | `127.0.0.1` behind Caddy (default) |
| `PORT` | `8080` by default |
| `APNS_TEAM_ID`, `APNS_KEY_ID` | Identifiers from your Apple account |
| `APNS_KEY_FILE` | Absolute path to your private APNs `.p8` file |
| `APNS_BUNDLE_ID` | Exact installed **app** identifier |
| `APNS_ENVIRONMENT` | `sandbox` for development profiles, `production` for distribution |

Start locally:

```sh
node --env-file=.env dist/src/server.js
```

`GET /health` reports process health only. Data endpoints require `Authorization: Bearer <owner token>`. Never put that token in a URL. The authenticated `/v1/status` endpoint reports APNs configuration, subscription IDs, next polling times and sanitized last errors. It does not return credentials or push tokens. Use the app's Test Connection to avoid putting secrets into shell history.

The app sends `PUT /v1/subscriptions/{id}` after consent and `DELETE` when disabling or disconnecting. Every subscription belongs to the single configured owner; there is no unauthenticated enrollment endpoint. If you need multiple unrelated users, add separate identities and per-user authorization rather than sharing this token.

## HTTPS deployment

1. Provision a persistent Node 24 host and a domain. Install Caddy using its official instructions, and point the domain to the server.
2. Copy the project and run `npm ci --ignore-scripts && npm run build`. Create a dedicated `fantasyglass` service account.
3. Place server environment configuration in `/etc/fantasyglass/backend.env`, APNs key outside the checkout, and the database under `/var/lib/fantasyglass`. Restrict access to that service account.
4. Adapt `fantasyglass.service.example` for your Node executable/install path and enable it with systemd. It uses a private temporary directory, a read-only system and a restricted writable database directory.
5. Adapt `Caddyfile.example` with your actual domain. Caddy terminates TLS and proxies only to loopback. Open inbound HTTPS and the ports needed for your chosen certificate challenge; do not expose the HTTP loopback service.
6. Confirm outbound HTTPS to ESPN/SportsDataIO and HTTP/2 TLS to Apple's APNs hosts. The APNs connection uses Node HTTP/2 directly; deployments with outbound proxies need a compatible HTTP/2 egress path. Don't disable TLS verification.
7. In the Push build, enter `https://your-domain`, save the owner token, test the connection, consent to encrypted server storage and enable remote mode. Allow notifications and re-pin the matchup.

Alternatively set `TLS_KEY_FILE` and `TLS_CERT_FILE` for native HTTPS. The server refuses a non-loopback bind without TLS. HTTP requests are limited to 128 KiB, rate-limited per socket IP, and data operations require constant-time bearer-token verification. Provider destinations are hardcoded/allowlisted; clients cannot submit arbitrary fetch URLs.

## Data handling and polling

Subscription payloads, ESPN cookies, optional SportsDataIO keys, frames and delivery payloads are encrypted with AES-256-GCM with fresh nonces. Database identifiers and deduplication fingerprints are metadata. Keep encrypted database backups and protect the encryption key separately. Losing the key makes old payloads unreadable. To rotate it, stop the service, retain any needed backup securely, start a new database with a new key and re-enroll from the app; don't simply change the key against the existing database.

The worker uses the same ESPN views and stat identifiers as the Swift adapter. A shared fixture contract checks decimal scoring in both implementations. JavaScript numeric coercion is avoided for provider score/stat tokens. SportsDataIO can replace only explicitly mapped, fully covered player lines; a feed failure retains ESPN and records a status note. The server never writes ESPN settings.

Polling defaults to 60 seconds with active NFL games, 120 seconds near kickoff, 15 minutes idle, and one hour for old finished weeks. Identical reads are cached briefly, keyed by credential identity. HTTP 429 respects Retry-After. Provider failures keep the last frame and record the provider failure; they never generate a fresh-looking zero score. NFL game-status failures also prevent unsupported notification transitions.

APNs uses ES256 JWTs, the exact app topic, priority 10 for alert pushes, a 4 KB payload limit and token invalidation. Version 1.0.1 removes all Live Activity update/end payloads and activity-token storage. The worker sends ordinary notification alerts only.

Alert transitions are detected on the server. Persistent event IDs and an encrypted outbox survive restarts; failed sends back off. APNs collapse IDs reduce duplicates. Delivery after an ambiguous network failure is at-least-once, not an exactly-once guarantee. Old alert pushes expire, and subscription data expires after 30 days without app synchronization. Disable remote mode before changing backend addresses so the old server can delete its subscriptions.

## Validate real delivery

The test suite validates request authorization, encryption, parser behavior, scoring, event transitions, cache retention, JWT signatures and payloads. It **does not prove** Apple delivery. No APNs key or iPhone was available in the development workspace.

On your physical device:

1. Install a correctly signed Push build and choose matching sandbox/production on the server.
2. Enable remote mode; Test Connection must report APNs configured.
3. Grant notification permission and confirm that device-token registration succeeds.
4. Exercise an enabled notification transition with controlled fixtures on a separate test server; then verify genuine game-day transitions. Never label synthetic fixture pushes as live football.
5. Reinstall/re-register and confirm token rotation removes queued alerts for the previous token.
6. Stop the server/network and confirm its status records a failure without inventing score changes.

Keep APNs keys out of the repository, do not enable request-body/header logging at the reverse proxy, and restrict operator access. Provider licenses and Apple policies still govern use.
