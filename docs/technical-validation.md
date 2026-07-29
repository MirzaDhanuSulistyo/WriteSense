# Technical Validation

## Decisions

- **Minimum platform:** macOS 14.
- **Application form:** SwiftUI menu bar application with an accessory activation policy.
- **Capture mechanism:** macOS Accessibility APIs; no keyboard event tap.
- **Capture unit:** Current paragraph around the Accessibility selection/cursor.
- **Snapshot storage:** Memory only.
- **Persistent storage:** AES-GCM encrypted Codable files with a 256-bit key in macOS Keychain.
- **Local language stack:** NaturalLanguage, NSSpellChecker, deterministic grammar/style rules, and optional Apple Foundation Models on eligible macOS 26 devices.

## Implemented feasibility path

`AccessibilityService`:

1. Resolves the frontmost process and focused Accessibility element.
2. Rejects unapproved applications before the service is called.
3. Detects known secure roles, password metadata, and detectable private-browser windows.
4. Reads the accessible value and selection range.
5. Extracts the current paragraph.
6. Applies only exact guarded replacements and refuses Terminal writes.

`AppModel` debounces paragraph changes, keeps snapshots in memory, produces structured diffs, learns patterns, and clears capture state when permission, application, context, or learning state changes.

## Unsupported or limited editor behavior

- Editors that do not expose a supported Accessibility text role or string value.
- Web editors that expose fragmented or stale Accessibility values.
- Editors that reject full-value writes.
- Private browser modes that cannot be identified from Accessibility metadata.
- Terminal screen buffers, which are intentionally copy-only.
- Empty fields, because no paragraph exists to review.
- Rich formatting that cannot survive an Accessibility full-value replacement.

Unsupported behavior fails without attempting repeated writes.

## Automated validation

The automated suite validates language analysis, diff extraction, multi-edit handling, classification, pattern generalization, app-scoped feedback, encrypted persistence, migration, retention, export, and deletion.

```sh
swift test
```

Accessibility APIs require real GUI processes and user-granted permissions, so application compatibility cannot be certified through unit tests. Use the manual checklist in [compatibility.md](compatibility.md) before entering Phase 7 or publishing compatibility claims.

## Exit assessment

The architecture is feasible for a limited supported-application prototype. Phase 0 code and documentation are present, but final acceptance still requires hands-on read/write verification in at least three target applications on a signed build.
