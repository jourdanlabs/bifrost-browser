# Security Policy

## Supported versions

BIFROST Browser is pre-1.0. Security fixes target the latest source on `main` and the newest published release.

## Reporting a vulnerability

Use GitHub’s private vulnerability reporting or a private security advisory for this repository. Do not open a public issue containing exploit details, browsing history, ledger contents, credentials, or personal data.

Include the affected commit or version, operating system, reproduction steps, impact, and whether the issue can cross the local-device boundary.

## Security model

- navigation evaluation and answer checks run locally;
- the app has no telemetry, account, or remote policy service;
- navigation decisions fail closed if the local ledger cannot be opened or appended;
- LUNA is tamper-evident but not encrypted;
- a `HOLD` continuation applies once to the exact request fingerprint and is recorded as `ABSTAIN`;
- answer verdicts are advisory deterministic heuristics, not security authorization.
