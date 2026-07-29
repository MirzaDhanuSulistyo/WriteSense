# WriteSense MVP Implementation Status

**Scope:** PRD Phases 0–6

**Current milestone:** MVP feature-complete; Phase 7 engineering hardening implemented with external beta validation still required.

## Phase summary

| Phase | Status | Evidence |
|---|---|---|
| 0 — Discovery and technical validation | Implemented; manual compatibility sign-off pending | Accessibility permission, focused-element capture, secure-field detection, paragraph extraction, and guarded replacement are implemented in `AccessibilityService.swift`. |
| 1 — Controlled text capture | Implemented | Menu bar status, pause, allowlist, custom apps, debounced in-memory snapshots, content-free session records, private/secure context blocking, and temporary-data deletion are implemented. |
| 2 — Edit detection and correction events | Implemented | `TextDiffEngine` creates multiple token-level edits and classifies insertions, deletions, replacements, word order, punctuation, and capitalization. Minimal correction events are retained separately from snapshots. |
| 3 — Personal pattern learning | Implemented | Generalized pattern keys, supporting examples, confidence, recency, conflict penalties, vocabulary learning, and pattern enable/delete controls are implemented. |
| 4 — Local grammar analysis | Implemented | Offline review, explanations, ranges, preview, apply, edit, reject, ignore, and undo are implemented. |
| 5 — Personalized suggestion ranking | Implemented | Generalized retrieval, application scoping, rejection suppression, tone preference, vocabulary protection, explanations, feedback history, and personalization reset are implemented. |
| 6 — Insights and user control | Implemented | Trends, counters, pattern examples, vocabulary management, recent correction events, per-event deletion, retention, export, per-app deletion, and complete deletion are implemented. |
| 7 — Reliability, privacy review, and beta | Engineering complete; external sign-off pending | Content-free diagnostics, compatibility probes, recovery, onboarding, feedback, packaging, and release documentation are implemented. Signed-build testing, independent review, and real beta evidence remain. |
| 8 — Optional cloud intelligence | Not started | Apple Foundation Models support is on-device and is not Phase 8 cloud processing. |

## Storage and privacy implementation

- Paragraph snapshots remain in memory and are discarded when a capture session resets.
- Persisted correction events contain only changed fragments and metadata, not full paragraphs.
- Profile, settings, activity history, diagnostics, and previous-write backups use AES-GCM encryption.
- The 256-bit encryption key is stored in macOS Keychain with a device-only accessibility class.
- Versioned payloads migrate existing plaintext and version-1 encrypted data; unreadable primaries recover from the previous encrypted backup when possible.
- Activity retention supports 0, 7, 30, 90, or 365 days.
- Content-free editing sessions and privacy audit actions follow the writing-activity retention setting.
- Opt-in diagnostics and compatibility history have a separate 30-day maximum.
- Complete deletion removes the application-support directory—including backups and run markers—and the Keychain key.
- Explicit exports are inspectable plaintext JSON and display a warning before saving.

## Automated coverage

The test suite covers:

- Deterministic local grammar behavior.
- Multi-edit token-level diffing.
- Word-order classification and whitespace suppression.
- Structured correction-event creation.
- Generalization across different verbs.
- Application-scoped personalization.
- Activity and diagnostic retention pruning.
- Encrypted round trips, schema migration, backup recovery, plaintext exclusion, export, and deletion.
- Content-free diagnostic export and summary calculations.
- Unclean-run markers and bounded long-paragraph diffing.
- Legacy settings migration.

Run it with:

```sh
swift test
```

## Manual work required before Phase 7 sign-off

Code cannot establish the following PRD acceptance criteria by itself:

1. Verify capture and replacement in real TextEdit, Notes, Mail, Safari, and Chrome releases.
2. Test secure fields, private browser windows, unsupported custom editors, and stale text ranges manually.
3. Measure capture success, suggestion precision, latency, undo rate, and crash-free sessions with real users.
4. Complete an independent privacy and security review.
5. Confirm deletion behavior on signed and notarized production builds.
6. Collect beta evidence that personalized suggestions outperform generic suggestions.

These are Phase 7 entry and beta-validation tasks rather than missing Phase 0–6 product features.
