# WriteSense

**Your writing, improved by your own habits.**

WriteSense is a privacy-first macOS menu bar writing coach. The private-beta candidate reads paragraphs only from explicitly approved applications through macOS Accessibility APIs, blocks secure fields, compares before/after text snapshots, and learns recurring edits locally.

## What is built

- SwiftUI menu bar application shell.
- Accessibility permission onboarding and visible Active/Paused/Blocked status.
- Allowlist for TextEdit, Notes, Mail, Safari, Chrome, and explicitly approved Terminal suggestions.
- Secure/password field blocking and no raw keystroke capture.
- Paragraph snapshots after a 900 ms typing pause (debounced).
- Token-aware before/after diffing with structured, minimal correction events.
- Generalized correction-pattern learning with conflict detection and application-aware ranking.
- Configurable encrypted activity retention, including a no-history mode.
- Offline language analysis using NaturalLanguage, NSSpellChecker, and deterministic local grammar/style rules.
- Optional on-device Deep Review with Apple Foundation Models on macOS 26+.
- Personalized ranking based on repeated edits and accepted/rejected suggestions.
- Accept, edit, reject, ignore, and undo suggestion actions.
- Persisted capitalization and writing-tone preferences.
- AES-GCM encrypted profile, settings, and activity files in `~/Library/Application Support/WriteSense`, with the encryption key stored in macOS Keychain.
- Plaintext profile export through an explicit save flow.
- Insights, weekly trends, recent correction events, vocabulary management, and per-pattern controls.
- Per-application deletion, personalization reset, and complete data-and-Keychain deletion.
- Five-step trust-oriented onboarding and permission recovery.
- Content-free local diagnostics, unclean-run detection, latency metrics, and compatibility probes.
- Structured local beta feedback export with no automatic upload.
- Versioned encrypted storage, previous-write backups, migration, and recovery.
- Hardened-runtime beta packaging with optional notarization and release checksums.

## Run

Requirements: macOS 14 or later. Building the optional Foundation Models integration requires Xcode 26 or later.

```sh
swift run WriteSense
```

For a regular `.app` bundle with an Accessibility permission identity:

```sh
./Scripts/build-app.sh
open build/WriteSense.app
```

For a tested beta archive and checksum:

```sh
./Scripts/package-beta.sh
```

External distribution requires a Developer ID Application signature and notarization; see [the beta release guide](docs/beta-release.md).

To run the real on-device Apple Foundation Models evaluation (12 tense forms and 18 grammar categories):

```sh
./Scripts/evaluate-foundation-model.sh
```

The evaluator exits with status 2 while Apple Intelligence reports that its model is unavailable or still downloading.

On first launch, grant WriteSense access under **System Settings → Privacy & Security → Accessibility**, then enable the applications you want to use. Terminal is listed but remains off by default because command lines can contain secrets. Apple Terminal exposes rendered screen text rather than a safely writable input field, so Terminal suggestions provide an explicit **Copy** action instead of direct replacement.

## Local language architecture

The first version intentionally does not require a cloud model:

- `NaturalLanguage` detects language and provides Apple's on-device linguistic context.
- `LocalLanguageEngine` applies fast, explainable offline grammar/style checks.
- `PatternLearner` turns repeated user corrections into a personal profile.
- `PersonalizationEngine` boosts relevant learned patterns and suppresses repeatedly rejected categories.

On macOS 26+, Deep Review uses Apple Foundation Models when Apple Intelligence is available. Older or unsupported Macs retain the complete deterministic local-review path.

## Local data lifecycle

- Paragraph snapshots exist only in memory while an editing session is active.
- Persisted correction events contain changed fragments rather than full paragraphs.
- Profile, settings, retained activity, diagnostics, and previous-write backups are encrypted with AES-GCM.
- The encryption key is generated locally and stored in macOS Keychain.
- Writing-activity retention can be disabled or set to 7, 30, 90, or 365 days.
- Optional content-free beta diagnostics are retained locally for up to 30 days and never uploaded automatically.
- Explicit writing, diagnostic, and feedback JSON exports are plaintext and should be reviewed and stored securely.
- Complete deletion removes primaries, backups, diagnostics, run markers, preferences, and the Keychain encryption key.

## Documentation

- [Product requirements](docs/macOS_Personalized_Writing_Coach_PRD.md)
- [MVP implementation status](docs/mvp-status.md)
- [Phase 7 status](docs/phase-7-status.md)
- [Private beta release guide](docs/beta-release.md)
- [Technical validation](docs/technical-validation.md)
- [Application compatibility matrix](docs/compatibility.md)
- [Privacy and data architecture](docs/privacy-and-data.md)
- [Internal security review](docs/security-review.md)
- [Known limitations](docs/known-limitations.md)
- [Support and troubleshooting](docs/support.md)
- [Beta feedback plan](docs/beta-feedback.md)
- [Monetization strategy](docs/monetize.md)
