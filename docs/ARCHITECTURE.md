# Architecture and Trust Boundaries

## Decision flow

```text
WKNavigationAction
  → NavigationContext
  → HEIMDALL policy evaluation
  → AURORA confidence calibration
  → LUNA append
  → allow | cancel | one-time HOLD continuation
```

The LUNA append occurs before the browser applies the decision. If the append fails, navigation is cancelled.

## Packages

- `HEIMDALLKit` defines policy rules and the four non-authorizing verdicts.
- `AURORAKit` deterministically maps raw policy scores to bounded confidence.
- `LUNAStore` appends and verifies the local hash-chained JSONL ledger.
- `BIFROSTKit` composes policy evaluation and ledger sealing into a navigation gateway.
- `BareBonesBrowserKit` owns WebKit, tabs, local UI, answer observation, and local stores.

## HOLD continuation

A held request is cancelled. If the user chooses `Continue once`, the exact method/URL/main-frame fingerprint is reissued once. Before WebKit receives `.allow`, BIFROST appends a second row with verdict `ABSTAIN` and reason `User affirmed a HOLD for this navigation one time.` The fingerprint is then consumed.

There is no persistent authorization state.

## Answer checks

The main-frame WebKit observer recognizes explicit `[data-bifrost-answer]` content and heuristic selectors on supported AI sites. Text is normalized and evaluated locally. The UI displays the input digest—not a LUNA receipt—because answer scans are not part of the navigation ledger schema.

The verifier detects output posture, not factual truth. A visible citation changes source posture but is not fetched or independently validated.

## Deliberate limits

- DOM selectors are provider-dependent and can drift.
- Trusted initiator and password-field evidence are not yet bridged from the page into `NavigationContext`; the corresponding HEIMDALL rule is dormant in the native adapter.
- Local ledger tamper evidence does not provide encryption, secure deletion, or protection from a user-account compromise.
- The app does not attempt to replace Safari/Chrome exploit mitigations, content blocking, or malware detection.
