# Support and Troubleshooting

## Accessibility permission is required

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable the signed WriteSense application.
3. Return to WriteSense and choose **Refresh permission status** in the setup guide, or reopen the menu.
4. If permission remains stale, remove the old WriteSense entry, quit the app, reopen the same signed app bundle, and grant access again.

Rebuilding with a different signing identity can create a new macOS privacy identity and require permission again.

## WriteSense says the application is blocked

Open **Settings → Approved applications** and enable the app explicitly. Custom apps can be added by activating the target app before selecting **Add current application**.

Do not approve sensitive applications merely to bypass a blocked status.

## No supported text field

- Focus a normal editable text field containing text.
- Check whether the app exposes macOS Accessibility values.
- Run **Beta diagnostics → Check last active app**.
- Consult [compatibility.md](compatibility.md) and [known-limitations.md](known-limitations.md).

Unsupported fields fail without repeated replacement attempts.

## Replacement failed

WriteSense cancels replacement if the paragraph or expected text changed after review. Focus the original field and run a new review. If the problem repeats, use Copy and submit a content-free beta report.

## Secure or private context blocked

This is expected safety behavior. WriteSense should not be enabled in that field or window. If a normal field is incorrectly blocked, report the application and version without sharing its text.

## Deep Review is unavailable

Deep Review requires macOS 26+, an Apple Intelligence-eligible Mac, Apple Intelligence enabled, and a downloaded/ready system model. The deterministic local review remains available on macOS 14+.

## Encrypted storage is unavailable

WriteSense pauses learning rather than overwrite unreadable data. It automatically attempts the previous encrypted backup. If recovery fails:

1. Preserve the application-support directory only if engineering support explicitly requests it and you can store it securely.
2. Use **Delete all data and preferences** to remove unreadable files and the Keychain key.
3. Re-run onboarding.

There is no password-reset mechanism for a missing device-only encryption key.

## Exporting diagnostics

Open **Beta diagnostics → Export report**. The JSON contains operation names, app identifiers, outcomes, timings, static error codes, and timestamps. Inspect it before sharing. It should never contain writing, changed fragments, vocabulary, or document names.

## Reset options

- Delete one correction event or learned pattern from Insights.
- Delete retained data for one application from Settings.
- Reset personalization while preserving app approvals and diagnostics.
- Clear diagnostics without deleting the writing profile.
- Delete all data, preferences, backups, run markers, and the Keychain key.

## Collecting a useful support report

Include:

- macOS version.
- WriteSense version and build.
- Target application name and version.
- Compatibility-check result.
- Exact steps, using invented sample text only.
- Exported content-free diagnostics if you consent.

Never include passwords, tokens, private writing, screenshots of sensitive documents, or unredacted client information.
