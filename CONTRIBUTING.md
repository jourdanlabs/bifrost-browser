# Contributing to BIFROST Browser

Thank you for helping improve BIFROST Browser.

## Before opening a change

- Use a focused branch and keep generated `build/` artifacts out of Git.
- Open an issue before large feature or policy changes so the trust boundary can be reviewed first.
- Never add an authorization verdict, persistent allowlist, remote telemetry, or autonomous action path.
- Keep answer-verifier claims calibrated to what the deterministic code actually proves.
- Do not change the LUNA row shape, genesis semantics, or chain verification without an explicit design proposal and migration tests.

## Validation

Every pull request must pass:

```bash
Scripts/oss-preflight.sh
Scripts/acceptance.sh
```

Add tests for behavior changes. Refusal and continuation changes must prove both the allowed and refused path, including the resulting LUNA row.

## Pull requests

Describe:

- what changed and why;
- user-visible behavior;
- trust or privacy impact;
- tests and manual checks performed;
- any remaining limitation.

Small, reviewable changes are preferred.

## Bugs and feature requests

Use GitHub Issues and include the app version, macOS/iOS version, reproduction steps, expected behavior, and actual behavior. Do not place security vulnerabilities or sensitive browsing data in a public issue; use the process in [SECURITY.md](SECURITY.md).
