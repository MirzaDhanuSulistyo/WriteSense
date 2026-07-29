# Private Beta Feedback Plan

## Target cohort

Recruit a small group of people who write frequently in English on macOS and primarily use TextEdit, Notes, Mail, Safari, or Chrome. Testers should understand that editor support is limited and agree to report problems without sharing private writing.

## In-app survey

Open **Settings → Beta and diagnostics → Provide beta feedback**. The survey collects:

- Overall usefulness, 1–5.
- Recommendation quality, 1–5.
- Trust and privacy clarity, 1–5.
- Whether the tester would keep learning enabled.
- Structured issue categories.
- Optional tester-written comments.
- Optional content-free diagnostic summary.

The app saves a reviewable JSON report. It never sends the report automatically. Testers must not paste passwords, access tokens, client writing, or other private content into comments.

## Content-free diagnostic summary

When explicitly included, the report may contain:

- App and macOS version.
- Completed and unclean-run counts.
- Crash-free run estimate.
- Local-review average and p95 latency.
- Replacement and permission failure counts.
- Secure-context block count.
- Compatibility-check count.
- Weekly active-day count.
- Retained suggestion acceptance rate.

It does not include paragraphs, correction fragments, suggestions, vocabulary, document names, comments from other reports, or hardware identifiers.

## Beta success targets

- No secure-field incident in tested scenarios.
- At least 90% of supported-app capture attempts complete without a crash.
- Local paragraph review p95 below 2 seconds on target Macs.
- Replacement failure and undo rates are understood and decreasing.
- At least 60% of respondents report that recommendations become more relevant.
- A majority keep learning enabled after one week.
- Trust rating averages at least 4/5.

These targets require real beta evidence; they cannot be satisfied by unit tests.

## Triage labels

| Priority | Examples |
|---|---|
| P0 | Secure text captured, data uploaded unexpectedly, deletion failure |
| P1 | Text corruption, repeatable crash, private-window capture |
| P2 | Unsupported editor, incorrect suggestion, permission recovery issue |
| P3 | Layout, explanation wording, minor workflow friction |

## Report handling

1. Ask the tester to inspect the JSON before sharing.
2. Store reports in access-controlled project storage.
3. Never request a writing excerpt unless separately consented and manually redacted.
4. Delete reports according to the beta research retention policy.
5. Aggregate ratings and content-free counters; do not build a corpus from tester writing.
