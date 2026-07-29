# Application Compatibility Matrix

This matrix distinguishes implemented behavior from manual release validation. Accessibility behavior can change between application versions, so every production release requires hands-on verification.

| Application | Capture design | Replacement design | Default | Validation status |
|---|---|---|---|---|
| TextEdit | Current paragraph through Accessibility value and selection range | Guarded full-value replacement with stale-range resolution | Enabled | Automated core logic passes; manual app test required |
| Apple Notes | Current accessible paragraph | Guarded replacement where the editor exposes a writable value | Enabled | Automated core logic passes; manual app test required |
| Apple Mail | Current accessible compose-field paragraph | Guarded replacement | Enabled | Automated core logic passes; manual app test required |
| Safari | Accessible text fields and text areas; detectable private windows blocked | Guarded replacement where supported | Disabled until approved | Manual browser/version test required |
| Google Chrome | Accessible text fields and text areas; detectable Incognito windows blocked | Guarded replacement where supported | Disabled until approved | Manual browser/version test required |
| Terminal | Active accessible command-line paragraph when a selection range exists | Never writes; explicit Copy action only | Disabled | Suggestion-only by design |
| Custom applications | Supported Accessibility text roles after explicit approval | Best effort with stale-range validation | Disabled | Per-application validation required |

## Secure and unsupported contexts

WriteSense blocks:

- `AXSecureTextField` elements.
- Elements with secure/password subroles.
- Elements exposing `AXIsPassword`.
- Detectable Safari private-browsing and Chrome Incognito windows.
- Applications not present in the explicit allowlist.
- Unsupported or unreadable Accessibility elements.

## Required manual release checklist

For each supported application and macOS release:

1. Verify permission onboarding and recovery after permission revocation.
2. Verify paragraph extraction at the beginning, middle, and end of a document.
3. Verify replacement and undo with repeated matching phrases.
4. Verify stale ranges cancel or resolve to the nearest exact text safely.
5. Verify secure/password fields return a blocked status.
6. Verify unsupported editors fail without repeated writes or crashes.
7. Verify pause and application revocation stop capture immediately.
8. Record app version, macOS version, success rate, and known limitations without raw text.

A production compatibility claim should be made only after this checklist is completed on a signed release build.
