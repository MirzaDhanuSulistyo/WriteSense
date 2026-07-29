# Privacy and Data Architecture

## Principles

WriteSense learns from final edits and explicit feedback. It does not install a keyboard event tap, record physical keystrokes, inspect the clipboard, capture screenshots, or upload writing.

## Capture boundaries

Text is considered only when all of the following are true:

- Accessibility permission is granted.
- Learning is enabled.
- The foreground application's bundle identifier is explicitly approved.
- The focused Accessibility element exposes a supported text role.
- The element is not a secure/password field.
- A detectable private-browser context is not active.

Terminal is disabled by default. When explicitly enabled, it is suggestion-and-copy only; WriteSense does not write into Terminal or learn patterns from its changing screen buffer.

## Data lifecycle

### Paragraph snapshots

Paragraph snapshots are held in memory during the active editing session. They are debounced after a typing pause, compared locally, and replaced by the newest snapshot. Session reset, pause, application changes, permission loss, and deletion discard them.

Snapshots are never written to disk.

### Correction events

A meaningful edit becomes a structured correction event containing:

- A random event and session identifier.
- Application name and bundle identifier.
- Changed fragment before and after the edit.
- Edit classification and writing category.
- Pattern identifier and timestamp.

Full paragraphs and document names are not retained in correction-event history. Changed fragments longer than 280 characters are treated as large rewrites and are not retained as events or pattern examples.

### Writing profile

The profile contains generalized patterns, a limited set of supporting changed-fragment examples, confidence and feedback counts, and personal vocabulary. Patterns may be disabled or deleted individually. Personalization can be reset without removing application approvals.

### Feedback history

Suggestion history contains category, outcome, personalization state, application identifier, pattern identifier, and timestamp. It does not contain the original sentence or replacement text.

### Session and privacy audit metadata

Editing-session records contain a random identifier, application identity, timestamps, and correction count. They contain no writing.

The local privacy audit records content-free actions such as permission requests, learning state changes, application approval/revocation, secure-context blocks, exports, and deletion operations. Repeated secure-context polling is deduplicated. Audit records follow the user's activity-retention setting and are never uploaded.

## Encryption

Profile, settings, and activity history are encoded locally and encrypted using AES-GCM with a randomly generated 256-bit key.

The key is stored as a generic password in macOS Keychain using `AfterFirstUnlockThisDeviceOnly`. Encrypted files are written atomically with owner-only file permissions where supported.

Prototype plaintext files are migrated on read. A plaintext source is removed only after its encrypted replacement has been written successfully. If encrypted data or its Keychain key cannot be opened, WriteSense pauses learning and refuses to overwrite the unreadable files; complete deletion is the explicit recovery path.

## Retention

Users can retain activity for 7, 30, 90, or 365 days, or select **Do not retain**. Retention applies to correction events, content-free suggestion feedback, editing sessions, and privacy audit events. Generalized profile patterns remain until reset or deletion because they power personalization.

Only changed fragments are retained as pattern examples. Full raw snapshots are never retained. In addition to time-based retention, local history is capped at 5,000 correction events, 10,000 feedback events, 5,000 sessions, and 2,000 privacy audit events.

## Export

Export is an explicit user action using a macOS save panel. The export contains the writing profile, retained activity, and settings in readable JSON.

Exports are intentionally plaintext for portability and inspection. The app warns users to store exported files securely. WriteSense cannot delete copies saved outside its application-support directory.

## Deletion controls

- **Delete today's activity:** removes today's retained corrections, feedback, sessions, prior audit events, and in-memory snapshots; a new content-free deletion audit marker may remain.
- **Delete correction event:** removes one retained event.
- **Delete application data:** removes retained events and attributable patterns for one application.
- **Reset personalization:** removes profile and history while preserving application approvals and settings.
- **Delete all data and preferences:** removes profile, history, settings, application approvals, in-memory snapshots, and the Keychain encryption key.

Deleting the encryption key cryptographically prevents remaining ciphertext from being decrypted if filesystem deletion is incomplete.

## Threat model

| Threat | Mitigation | Residual risk |
|---|---|---|
| Accidental capture in an unapproved application | Bundle-ID allowlist checked before every capture | A user can explicitly approve a sensitive application |
| Password or token capture | Secure roles, secure/password subroles, and `AXIsPassword` fail closed | Custom controls may expose incomplete Accessibility metadata |
| Private-browser capture | Detectable Safari private and Chrome Incognito window titles are blocked | Browser metadata and titles can change; release testing is required |
| Raw-key surveillance | No keyboard event tap and no physical-key event storage | Paragraph snapshots necessarily contain currently visible text in memory |
| Local disk disclosure | AES-GCM files, device-only Keychain key, owner-only permissions | An attacker controlling an unlocked user session may access app data |
| Incorrect or stale replacement | Exact-text validation, nearest-match resolution, guarded writes, and undo | Third-party editors can change between validation and write |
| Sensitive diagnostics | No current upload; raw text is prohibited from future diagnostics | Future telemetry changes require review |
| Plaintext export disclosure | Explicit save action and warning | Files saved by users are outside WriteSense deletion control |
| Deleted ciphertext recovery | Application files and Keychain key are deleted | SSD/filesystem behavior prevents guaranteed physical overwrite; key deletion provides cryptographic erasure |

## Diagnostics

The current application does not upload diagnostics or analytics. Future diagnostics must contain event types, category identifiers, counts, latency, and error codes only. Raw text, changed fragments, vocabulary, document names, and exports are prohibited from diagnostics.

## Known detection limits

Accessibility behavior varies by editor. Private-browser detection relies on detectable Accessibility window metadata and cannot be guaranteed for every browser release. If a field cannot be classified or read safely, WriteSense fails closed and does not capture it.
