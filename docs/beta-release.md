# Private Beta Release Guide

## Build prerequisites

- macOS 14 or later.
- Swift 6 / current Xcode command-line tools.
- Apple Developer ID Application certificate for external distribution.
- A `notarytool` Keychain profile for notarization.
- Xcode 26+ only when compiling the optional Foundation Models integration.

## Local beta archive

```sh
./Scripts/package-beta.sh
```

This runs the test suite, creates a hardened-runtime app, verifies its code signature, packages a ZIP, and writes a SHA-256 checksum under `build/releases/`. Without distribution credentials it emits explicit signature/notarization warnings.

## Signed and notarized archive

```sh
export CODESIGN_IDENTITY='Developer ID Application: Example Company (TEAMID)'
export NOTARY_KEYCHAIN_PROFILE='writesense-notary'
export REQUIRE_NOTARIZATION=1
export RELEASE_VERSION='0.2.0-beta.1'
export APP_VERSION='0.2.0'
export BUILD_NUMBER='2'
./Scripts/package-beta.sh
```

The script fails closed when notarization is required but credentials or a Developer ID signature are missing.

## Release checklist

1. `swift test` passes.
2. Release build and strict code-sign verification pass.
3. Notarization succeeds and the ticket is stapled.
4. ZIP checksum is recorded with the release.
5. Manual compatibility checklist is completed on the exact archive.
6. Secure fields and detectable private windows are tested in every claimed app version.
7. Accessibility permission grant, revocation, and restoration are tested.
8. Replacement, stale-range cancellation, and undo are tested using invented text.
9. Encrypted migration, backup recovery, export, and complete deletion are tested on a disposable profile.
10. Diagnostic export is inspected for prohibited raw content.
11. Known limitations and support documentation are included with the invitation.
12. Beta feedback handling and retention owners are assigned.

## Distribution notes

- Distribute only the notarized ZIP and its checksum.
- Do not send ad-hoc or Apple Development-signed builds to external testers.
- Keep bundle identifier and signing identity stable so macOS Accessibility approval remains valid.
- Every rebuilt or re-signed beta may need fresh compatibility and permission testing.

## Rollback

Keep the previous notarized archive and checksum. Data files preserve one encrypted backup, but application rollback must still be tested against the current schema. Never promise recovery from a newer unsupported schema without a migration test.
