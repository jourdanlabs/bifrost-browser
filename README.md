# BIFROST Browser

BIFROST Browser is a local-first macOS and iOS browser experiment that puts a deterministic refusal gate in front of web navigation and exposes plain-language evidence when it intervenes.

It is a guardrail, not an oracle and not an actuator. The navigation engine can return only `NO_OBJECTION`, `ABSTAIN`, `HOLD`, or `REFUSE`. It has no authorization verdict and no persistent “allow forever” path.

This project is derived from [DuckDuckGo BareBonesBrowser](https://github.com/duckduckgo/BareBonesBrowser) under Apache-2.0. The fork point and attribution are recorded in [NOTICE.md](NOTICE.md).

## Current status

- macOS: functional pre-1.0 browser and Developer ID release pipeline
- iOS: source and generic-device substrate builds pass; not App Store-ready
- release line: `0.1.3`
- telemetry, accounts, sync, and remote policy services: none

## What works

- `WKWebView` browser with tabs, bookmarks, address/search, standard shortcuts, and target-blank handling
- HEIMDALL navigation evaluation on every WebKit navigation request
- one-time human continuation for `HOLD`; the continuation is sealed as `ABSTAIN`, never as authorization
- local user blocklist with hard `REFUSE`
- AURORA deterministic confidence calibration
- LUNA append-only, hash-chained navigation ledger with verification and export
- local AI-answer posture checks on explicit fixtures and supported ChatGPT, Claude, Gemini, Perplexity, Poe, Copilot, and Grok surfaces
- browser-first navigation-state and answer-scan pills, scanning state, and read-only evidence drawers
- first-run onboarding and local inspector for policy, ledger, and blocklist

## Trust contract

`NO_OBJECTION` is a navigation policy result, not authorization. Answer scan results never approve or reject an answer. `NO SCAN FLAG` means only that this version's configured text-pattern checks did not match; `REVIEW` means one did.

The answer scanner is intentionally narrow. It looks for patterns such as possible contradictions, repeated certainty language, recency terms without visible source markers, and dense numeric content. It does not fetch citations, independently validate sources, or replace domain review.

Known boundaries:

- provider DOM changes can break answer detection;
- answer scans are local heuristic checks and are not written into the navigation LUNA ledger;
- the current native navigation adapter does not supply trusted DOM credential-field or initiator-origin evidence, so the cross-origin credential rule exists in the engine but is not live on browser navigation yet;
- the LUNA ledger is tamper-evident, not encrypted, and records navigation metadata locally;
- iOS is a buildable substrate, not a finished mobile product.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [PRIVACY.md](PRIVACY.md) for the complete boundary.

## Build and test

Requirements:

- macOS 14 or later
- Xcode with macOS and iOS SDKs
- Swift 5.9 or later

Run the complete acceptance gate:

```bash
Scripts/oss-preflight.sh
Scripts/acceptance.sh
```

The iOS acceptance leg builds a generic device target so it does not depend on a specifically named simulator. To target an installed simulator explicitly:

```bash
IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17' Scripts/acceptance.sh
```

Build only the macOS app:

```bash
xcodebuild \
  -project BareBonesBrowser.xcodeproj \
  -scheme BareBonesBrowser \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Signed macOS release

`Scripts/package-mac.sh` archives, Developer ID-signs, notarizes, staples, Gatekeeper-validates, and hashes the app, zip, and DMG. It never contains signing secrets; release authority stays in the operator’s keychain.

```bash
BIFROST_VERSION=0.1.3 \
BIFROST_TEAM_ID=YOUR_TEAM_ID \
BIFROST_NOTARY_PROFILE=YOUR_KEYCHAIN_PROFILE \
BIFROST_DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)' \
Scripts/package-mac.sh
```

Generated artifacts live under ignored `build/` paths.

## Local data

Unsandboxed development builds use:

- ledger: `~/Library/Application Support/BIFROST/luna-ledger.jsonl`
- bookmarks: `~/Library/Application Support/BIFROST/bookmarks.json`
- blocklist: `~/Library/Application Support/BIFROST/blocklist.json`
- exports: `~/Library/Application Support/BIFROST/exports/`

Sandboxed app builds place the same relative paths inside the application container.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), run both preflight scripts, and keep the central invariant intact: always the brake, never the sword.

Security reports should follow [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
