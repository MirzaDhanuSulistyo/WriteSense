# Internal Security Review

**Review type:** Engineering self-review

**Scope:** WriteSense private-beta build, Phases 0–7

**External assessment:** Not yet completed

This document records an internal review and must not be represented as an independent audit, penetration test, or compliance certification.

## Reviewed surfaces

- macOS Accessibility capture and replacement.
- Application allowlisting and sensitive-context blocking.
- In-memory snapshots and structured correction events.
- Pattern learning and on-device model prompts.
- Encrypted profile, settings, history, backups, and migration.
- Keychain key lifecycle.
- Export, diagnostics, feedback, and deletion workflows.
- Beta build signing and notarization pipeline.

## Implemented controls

### Capture boundaries

- Every automatic capture checks the current bundle identifier against the explicit allowlist.
- Known secure roles, password subroles, and `AXIsPassword` fail closed.
- Detectable Safari private windows and Chrome Incognito windows are blocked.
- Unsupported or unreadable Accessibility elements return a typed failure without replacement attempts.
- Terminal remains off by default, does not produce learned diffs, and is Copy-only.

### Replacement safety

- Replacement requires the expected original substring.
- Stale ranges resolve only to the nearest exact text match.
- Terminal writes are prohibited.
- Failed replacement attempts produce only content-free diagnostic codes.
- Successful changes have an immediate undo record.

### Local data protection

- Sensitive Codable payloads use AES-GCM with a random 256-bit key.
- The key uses macOS Keychain with `AfterFirstUnlockThisDeviceOnly`.
- Files and directories receive owner-only permissions where supported.
- Writes are atomic and preserve a previous encrypted backup.
- Payloads include a schema version; legacy plaintext and version-1 encrypted files migrate locally.
- Corrupt primary data can recover from the last known-good encrypted backup.
- Recovered settings fail closed: learning, diagnostics, and application approvals are paused until the user reviews setup again.
- If neither primary nor backup is readable, learning pauses and the unreadable files are not overwritten.

### Data minimization

- Paragraph snapshots remain in memory.
- Correction history stores changed fragments, not full paragraphs.
- Large changed spans are excluded from retained learning.
- Diagnostic events contain operation identifiers, booleans, durations, bundle identifiers, static error codes, and timestamps only.
- The unclean-run marker contains only a UUID and timestamp.
- No diagnostic or feedback report is uploaded automatically.

### Deletion

- Per-event, per-pattern, per-application, daily, personalization-reset, diagnostic-clear, and complete-deletion workflows exist.
- Complete deletion removes encrypted primaries, backups, run markers, settings, diagnostics, and the Keychain key.
- User-created exports remain outside application control.

## Residual risks

| Risk | Severity | Current disposition |
|---|---:|---|
| A custom editor may expose sensitive text without secure Accessibility metadata | High | Fail closed where metadata is incomplete; maintain a limited tested compatibility list |
| Safari/Chrome private-mode metadata may change | High | Manual test every supported browser release; document that detection is best effort |
| Full-value Accessibility writes can affect rich formatting | High | Limit supported editors, validate exact text, publish limitation, require explicit Apply |
| An attacker controlling an unlocked user session may query Accessibility or Keychain data | High | Outside protection offered by local at-rest encryption; no compliance claim |
| Atomic-write backups retain one prior encrypted value | Medium | Backups use the same encryption and complete deletion removes files and key |
| Filesystem/SSD deletion cannot guarantee physical overwrite | Medium | Key deletion supplies cryptographic erasure for app-managed ciphertext |
| Beta comments may contain sensitive text entered by a tester | Medium | Explicit warning, 4,000-character cap, local save panel, no automatic upload |
| An unclean marker can classify force quit or power loss as a possible crash | Low | UI and reports label this as an unclean run, not a proven crash |

## Required external work

Before a public or regulated deployment:

1. Independent macOS security review and targeted penetration testing.
2. Hands-on secure-field testing in every claimed application/version.
3. Review of Keychain access behavior on signed and notarized builds.
4. Verification that exported diagnostics contain no writing under fuzzed inputs.
5. Review of browser private-mode detection on every supported update.
6. Threat-model update before adding networking, synchronization, or cloud analysis.

## Review conclusion

The implemented controls are appropriate for a limited private beta with clearly published limitations. This self-review does not justify compliance, regulated-industry, or universal editor-safety claims.
