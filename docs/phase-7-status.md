# Phase 7 Status — Reliability, Privacy Review, and Beta

## Engineering status

The Phase 7 engineering scope is implemented for private-beta preparation:

- Content-free local diagnostics and explicit export.
- Unclean-run detection and crash-free run estimation.
- Review, diff, replacement, permission, and compatibility metrics.
- In-app compatibility probe that never retains field text.
- Permission revocation and restoration handling.
- Bounded long-paragraph review and diff behavior.
- Guided five-step onboarding.
- Structured beta feedback report with optional diagnostic summary.
- Versioned encrypted payloads, previous-write backups, migration, and automatic recovery.
- Hardened-runtime beta packaging, signature verification, optional notarization, and checksums.
- Privacy, security, compatibility, limitations, support, feedback, and release documentation.

## Deliverables

| PRD deliverable | Repository artifact |
|---|---|
| Beta-ready build | `Scripts/package-beta.sh`, `Scripts/build-app.sh`, `Scripts/WriteSense.entitlements` |
| Privacy documentation | `privacy-and-data.md` |
| Security review report | `security-review.md` |
| Compatibility matrix | `compatibility.md` plus the in-app compatibility probe |
| Feedback survey | `beta-feedback.md` plus the Beta Feedback window |
| Known limitations | `known-limitations.md` |
| Support guide | `support.md` |

## Acceptance status

| Criterion | Status |
|---|---|
| No raw user text appears in logs | Enforced by diagnostic schemas and tests; final signed-build inspection remains required |
| Secure fields remain blocked | Implemented; hands-on testing per supported app/version remains required |
| Permission changes recover | Implemented and instrumented; signed-build manual test remains required |
| Unsupported editors do not crash | Typed fail-closed paths implemented; editor matrix testing remains required |
| Core latency is acceptable | Instrumented and bounded; target-hardware beta measurements remain required |
| Active state is understandable | Persistent menu status and guided onboarding implemented; user study remains required |
| Users can fully delete data | Implemented, including backups, diagnostics, marker, preferences, and Keychain key; signed-build verification remains required |

## What cannot be completed in source code alone

Phase 7 is not signed off until the team:

1. Produces a Developer ID-signed and notarized archive.
2. Runs the manual compatibility matrix on the exact archive.
3. Completes an independent privacy/security review.
4. Collects real crash-free, latency, trust, retention, and recommendation-quality beta metrics.
5. Confirms no secure-field incident and validates deletion on tester-equivalent systems.

The repository is private-beta ready from an engineering perspective, but external evidence remains an explicit release gate.
