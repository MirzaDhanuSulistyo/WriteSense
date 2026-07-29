# Known Limitations

## Application compatibility

- macOS Accessibility implementations vary by application and release.
- Rich-text and web editors may expose fragmented, stale, read-only, or full-document values.
- Full-value replacement can lose formatting in editors that do not support precise range writes.
- Only applications and versions that complete the manual compatibility checklist should be advertised as supported.
- Empty fields cannot be reviewed until text exists.

## Sensitive-context detection

- Secure-field blocking depends on Accessibility role, subrole, and password metadata supplied by the target application.
- Private-browser detection is best effort and depends on window metadata that Safari or Chrome may change.
- Users should not approve password managers, banking tools, authentication apps, secure-note tools, or other sensitive applications.

## Terminal

- Terminal is disabled by default.
- Its Accessibility tree represents rendered screen content rather than a safely writable command line.
- Terminal suggestions are Copy-only and never create learned correction events.

## Language quality

- The deterministic engine supports English and a finite set of explainable rules; it is not a complete grammar parser.
- Apple Foundation Models Deep Review requires an eligible Mac, macOS 26+, Apple Intelligence enabled, and a ready local model.
- On-device model suggestions can still be incorrect and always require user approval.
- Generalized personal patterns can overgeneralize; users can reject, disable, delete, or reset them.

## Performance

- Interactive review is limited to 12,000 UTF-16 code units per paragraph.
- Very long diffs use a bounded linear fallback instead of the full token LCS.
- Long documents are reviewed one paragraph at a time.
- Accessibility polling runs at a low frequency but may still affect battery life during long sessions.

## Diagnostics and crash estimation

- Diagnostics are local and content-free; there is no automatic crash-upload service.
- Crash-free rate is inferred from a launch marker. Force quit, power loss, debugger termination, or OS shutdown can appear as an unclean run.
- Disabling diagnostics removes local diagnostic and compatibility history.

## Storage and recovery

- Recovery can roll back one encrypted write by using the previous backup. If settings are recovered, learning, diagnostics, and application approvals are intentionally paused for safety.
- If the Keychain key and backups are unavailable, encrypted data cannot be recovered; the explicit recovery path is complete deletion.
- User-created plaintext exports are not controlled or deleted by WriteSense.
- SSD behavior prevents guaranteed physical overwrite, though deleting the encryption key cryptographically erases app-managed ciphertext.

## Distribution

- Local development signatures are not suitable for external beta distribution.
- External archives require a Developer ID Application signature and Apple notarization.
- The repository does not claim App Store readiness, enterprise administration, cloud sync, or regulated-industry compliance.
