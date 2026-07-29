# WriteSense

**Your writing, improved by your own habits.**

WriteSense is a privacy-first macOS menu bar writing coach. The prototype reads paragraphs only from explicitly approved applications through macOS Accessibility APIs, blocks secure fields, compares before/after text snapshots, and learns recurring edits locally.

## What is built

- SwiftUI menu bar application shell.
- Accessibility permission onboarding and visible Active/Paused/Blocked status.
- Allowlist for TextEdit, Notes, Mail, Safari, Chrome, and explicitly approved Terminal suggestions.
- Secure/password field blocking and no raw keystroke capture.
- Paragraph snapshots after a 900 ms typing pause (debounced).
- Local before/after diffing and correction-pattern learning.
- Offline language analysis using NaturalLanguage, NSSpellChecker, and deterministic local grammar/style rules.
- Optional on-device Deep Review with Apple Foundation Models on macOS 26+.
- Personalized ranking based on repeated edits and accepted/rejected suggestions.
- Accept, edit, reject, ignore, and undo suggestion actions.
- Persisted switch for enabling or disabling sentence-capitalization suggestions.
- Local JSON profile storage in `~/Library/Application Support/WriteSense`.
- Insights, pattern controls, and complete data deletion.

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
