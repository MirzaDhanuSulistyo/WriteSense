# Product Requirements Document (PRD)
## Personalized Writing Coach for macOS

**Document status:** Draft
**Version:** 1.0
**Platform:** macOS
**Primary format:** Menu bar application
**Primary users:** People who write frequently in English and want a writing assistant that learns from their edits and preferences
**Last updated:** July 29, 2026

---

## 1. Product Summary

The Personalized Writing Coach is a macOS application that observes text changes in user-approved applications, identifies recurring writing and grammar patterns, and provides personalized recommendations.

The product is not intended to operate as a traditional spell checker or keylogger. It should learn from the difference between an earlier version of a sentence or paragraph and the final version produced by the user.

The application should:

- Read text only from supported and user-approved text fields.
- Detect how the user edits and improves their writing.
- Identify recurring grammar and style patterns.
- Learn which recommendations the user accepts or rejects.
- Provide personalized suggestions based on previous corrections.
- Process data locally by default.
- Never capture passwords, PINs, secure fields, screenshots, or raw keystroke logs.

---

## 2. Problem Statement

Traditional grammar tools provide generic corrections. They often fail to understand a user's preferred tone, vocabulary, recurring mistakes, or writing habits.

Users need a writing assistant that improves over time by learning from:

- Their manual corrections.
- Their accepted and rejected suggestions.
- Their vocabulary.
- Their preferred tone.
- Their repeated grammar patterns.
- Their final version of a message, paragraph, or document.

The main challenge is learning from user writing without creating a surveillance-style experience.

---

## 3. Product Vision

Build a private macOS writing coach that understands how a user writes and becomes more useful with every approved interaction.

The product should feel like a personal editor, not a monitoring tool.

### Product principle

> Learn from final edits and explicit feedback, not from hidden raw-key recording.

---

## 4. Goals

### 4.1 Primary goals

1. Capture text snapshots from supported macOS applications with explicit user permission.
2. Detect meaningful differences between initial and final text.
3. Convert repeated edits into reusable writing patterns.
4. Provide grammar and style recommendations personalized to the user.
5. Let the user understand, accept, reject, edit, and undo every recommendation.
6. Keep data local by default.
7. Make all monitoring visible and controllable.

### 4.2 Secondary goals

- Show writing improvement over time.
- Support a personal vocabulary and custom terminology.
- Learn tone preferences by application or context.
- Support optional cloud-based analysis later.
- Allow users to export or delete their personal writing profile.

### 4.3 Non-goals for the first version

The first version will not:

- Record every physical keystroke.
- Read every text field in every application.
- Train a large language model from scratch.
- Automatically rewrite text without user approval.
- Capture passwords or secure input.
- Monitor Terminal, password managers, or financial applications by default.
- Analyze screenshots.
- Monitor clipboard contents.
- Support team or enterprise administration.
- Synchronize user data across devices.
- Guarantee compatibility with all custom text editors.

---

## 5. Target Users

### 5.1 Primary user

A professional or student who:

- Writes messages, emails, notes, or documents in English.
- Makes repeated grammar mistakes.
- Wants personalized feedback.
- Values privacy.
- Is willing to grant Accessibility permission to a trusted application.
- Wants the assistant to improve based on past edits.

### 5.2 Example user stories

- As a user, I want the app to notice that I frequently use incorrect verb tense.
- As a user, I want suggestions based on corrections I previously made.
- As a user, I want to block the app from reading certain applications.
- As a user, I want to pause learning immediately.
- As a user, I want to know why a suggestion is personalized.
- As a user, I want to remove a learned pattern that is incorrect.
- As a user, I want the app to ignore technical vocabulary I use frequently.
- As a user, I want all processing to remain on my Mac.
- As a user, I want to delete all stored writing data.

---

## 6. Core Product Experience

### 6.1 First-run experience

The onboarding flow should:

1. Explain what the product reads.
2. Explain what the product never reads.
3. Request macOS Accessibility permission.
4. Ask the user to select approved applications.
5. Let the user choose local-only processing.
6. Show a sample text-learning interaction.
7. Confirm that monitoring can be paused from the menu bar.

### 6.2 Learning flow

```text
User types in an approved application
        ↓
Application detects a supported focused text field
        ↓
Application stores a temporary paragraph snapshot
        ↓
User edits the paragraph
        ↓
Application compares earlier and later versions
        ↓
Application extracts meaningful changes
        ↓
Application groups similar changes into patterns
        ↓
Application updates the personal writing profile
```

### 6.3 Suggestion flow

```text
Current sentence or paragraph
        +
Relevant learned patterns
        +
User writing preferences
        ↓
Grammar and style analysis
        ↓
Ranked personalized suggestions
        ↓
User accepts, rejects, edits, or ignores
        ↓
Preference model is updated
```

### 6.4 Menu bar experience

The menu bar interface should show:

- Current status: Active, Paused, or Blocked.
- Current application being analyzed.
- Pause learning.
- Review current paragraph.
- Open recent suggestions.
- Open writing insights.
- Open application permissions.
- Delete today's data.
- Open settings.

---

## 7. Functional Requirements

## 7.1 Application access

The application must:

- Use macOS Accessibility APIs to identify the focused application.
- Detect the focused accessible text element.
- Read text only from approved applications.
- Check whether the focused field is secure.
- Stop processing when a field is unsupported or sensitive.
- Show the current capture status in the menu bar.
- Allow the user to revoke application access at any time.

## 7.2 Text snapshot capture

The application must:

- Capture text around the active cursor, preferably the current paragraph.
- Avoid storing full documents when a paragraph is sufficient.
- Capture snapshots after a typing pause or explicit review action.
- Avoid generating snapshots on every keypress.
- Store snapshots temporarily until the related editing session is resolved.
- Discard snapshots that contain no meaningful changes.

## 7.3 Change detection

The application must:

- Compare earlier and later text versions.
- Detect inserted, deleted, replaced, and reordered text.
- Ignore insignificant formatting changes.
- Preserve sentence and paragraph boundaries.
- Identify the smallest useful changed phrase.
- Record whether a change was manual or suggested by the product.

## 7.4 Pattern learning

The learning engine must:

- Group similar corrections.
- Track how often a pattern occurs.
- Track when the pattern was last observed.
- Assign a confidence score.
- Distinguish grammar patterns from vocabulary preferences.
- Distinguish writing-style preferences from factual corrections.
- Reduce confidence when the user rejects related suggestions.
- Let the user remove or disable a learned pattern.

## 7.5 Personalized suggestions

The product must:

- Analyze the current sentence or paragraph.
- Retrieve relevant learned patterns.
- Rank suggestions using personal history.
- Explain the grammar or style issue.
- Explain why the suggestion is personalized.
- Allow accept, reject, edit, ignore, and undo actions.
- Never replace text automatically without approval.

## 7.6 Personal vocabulary

The product must:

- Learn commonly used names, product terms, and technical words.
- Let the user add words manually.
- Let the user remove learned words.
- Avoid repeatedly suggesting changes to accepted terminology.
- Support case-sensitive terms where appropriate.

## 7.7 Writing profile

The application should maintain a summarized profile containing:

- Preferred language.
- Preferred English variant.
- Preferred level of formality.
- Common grammar patterns.
- Common style preferences.
- Frequently accepted recommendations.
- Frequently rejected recommendations.
- Personal vocabulary.
- Application-specific preferences.

## 7.8 Insights dashboard

The dashboard should show:

- Most frequent grammar patterns.
- Most frequent manual corrections.
- Suggestions accepted and rejected.
- Improvement trends.
- Recently learned preferences.
- Personal vocabulary.
- Applications where learning is enabled.
- Data storage and deletion controls.

---

## 8. Privacy and Security Requirements

Privacy is a core product requirement, not a later enhancement.

### 8.1 Default behavior

The product must:

- Process text locally by default.
- Never record raw keystrokes.
- Never capture passwords, PINs, one-time codes, or secure text.
- Never monitor clipboard contents.
- Never capture screenshots.
- Never activate in blocked applications.
- Never upload text without explicit consent.
- Display a visible active or paused state.

### 8.2 Application controls

The user must be able to:

- Approve applications individually.
- Block applications individually.
- Pause learning globally.
- Pause learning temporarily.
- Delete data for the current day.
- Delete data for one application.
- Delete individual learned patterns.
- Delete all personal data.

### 8.3 Sensitive application defaults

The application should block these categories by default:

- Password managers.
- Banking and financial applications.
- Authentication utilities.
- Terminal applications.
- Remote desktop applications.
- Private browser windows where detectable.
- System password dialogs.
- Secure note applications.

### 8.4 Data protection

The application must:

- Encrypt sensitive local data at rest.
- Store encryption keys in macOS Keychain.
- Minimize storage of raw text.
- Prefer extracted patterns over long-term raw text storage.
- Set a configurable retention period.
- Record privacy-relevant actions in a local audit log.
- Never include raw user text in diagnostic logs.

---

## 9. Data Model

### 9.1 Editing session

```json
{
  "session_id": "uuid",
  "application_bundle_id": "com.apple.Notes",
  "document_context": "optional-local-identifier",
  "started_at": "timestamp",
  "last_updated_at": "timestamp",
  "language": "en",
  "status": "active"
}
```

### 9.2 Text snapshot

```json
{
  "snapshot_id": "uuid",
  "session_id": "uuid",
  "text": "I already send the email yesterday.",
  "cursor_location": 34,
  "captured_at": "timestamp",
  "retention_state": "temporary"
}
```

### 9.3 Correction event

```json
{
  "event_id": "uuid",
  "session_id": "uuid",
  "application_bundle_id": "com.apple.Notes",
  "original_text": "I already send the email yesterday.",
  "final_text": "I already sent the email yesterday.",
  "changed_fragment_before": "send",
  "changed_fragment_after": "sent",
  "change_source": "manual_user_edit",
  "language": "en",
  "created_at": "timestamp"
}
```

### 9.4 Learned pattern

```json
{
  "pattern_id": "uuid",
  "category": "verb_tense",
  "description": "Past event expressed using present-tense verb",
  "example_before": "I already send it yesterday.",
  "example_after": "I already sent it yesterday.",
  "occurrence_count": 7,
  "acceptance_count": 4,
  "rejection_count": 1,
  "confidence": 0.84,
  "enabled": true,
  "last_observed_at": "timestamp"
}
```

### 9.5 Suggestion event

```json
{
  "suggestion_id": "uuid",
  "pattern_id": "uuid",
  "original_text": "I already send the report.",
  "suggested_text": "I already sent the report.",
  "explanation": "Use past tense for a completed action.",
  "personalization_reason": "You made a similar correction seven times.",
  "confidence": 0.91,
  "outcome": "accepted",
  "created_at": "timestamp"
}
```

---

## 10. Technical Architecture

### 10.1 macOS application layer

Recommended components:

- Swift.
- SwiftUI.
- Menu bar application.
- Accessibility API integration.
- Local database.
- Local text-difference engine.
- Local grammar-analysis layer.
- Personalization and ranking engine.
- Settings and privacy controls.

### 10.2 Core services

#### Accessibility Service

Responsibilities:

- Detect focused application.
- Detect focused UI element.
- Read accessible text.
- Read selected text and cursor range.
- Replace text when supported.
- Detect unsupported and secure fields.

#### Session Manager

Responsibilities:

- Start and stop editing sessions.
- Manage temporary snapshots.
- Detect typing pauses.
- Prevent duplicate snapshots.
- Close inactive sessions.

#### Diff Engine

Responsibilities:

- Compare snapshots.
- Extract changed spans.
- Normalize punctuation and whitespace.
- Classify edit types.
- Produce structured correction events.

#### Pattern Engine

Responsibilities:

- Cluster similar correction events.
- Calculate pattern confidence.
- Maintain frequency and recency.
- Update confidence based on user feedback.
- Suppress weak or conflicting patterns.

#### Grammar Engine

Responsibilities:

- Analyze sentence structure.
- Identify grammar and style issues.
- Return structured suggestions.
- Operate locally for the first prototype.
- Accept personalized context from the Pattern Engine.

#### Suggestion Ranker

Responsibilities:

- Rank grammar findings.
- Boost relevant personal patterns.
- Lower ranking for repeatedly rejected suggestions.
- Avoid suggestions that conflict with personal vocabulary.
- Produce a personalization explanation.

#### Privacy Guard

Responsibilities:

- Check application allowlist.
- Check application blocklist.
- Detect secure fields.
- Detect prohibited contexts.
- Redact data from logs.
- Stop all processing while paused.

#### Local Storage Service

Responsibilities:

- Store sessions, events, patterns, preferences, and settings.
- Encrypt sensitive records.
- Apply retention rules.
- Support data deletion.
- Support local export.

---

## 11. Implementation Phases

# Phase 0 — Discovery and Technical Validation

### Objective

Confirm that the proposed macOS architecture can reliably read and update text in a limited set of target applications.

### Scope

Test:

- Accessibility permission flow.
- Focused application detection.
- Focused text element detection.
- Text extraction.
- Selected-range extraction.
- Text replacement.
- Secure-field detection.
- Compatibility with selected applications.

### Initial target applications

- TextEdit.
- Apple Notes.
- Apple Mail.
- Safari text areas.
- Chrome text areas.

### Deliverables

- Technical feasibility report.
- Compatibility matrix.
- List of unsupported editor behaviors.
- Initial privacy threat model.
- Decision on local storage technology.
- Decision on supported minimum macOS version.

### Acceptance criteria

- The prototype can detect the focused application.
- The prototype can read text from at least three target applications.
- The prototype can identify secure fields and refuse access.
- The prototype can replace selected text in at least two target applications.
- Accessibility permission state can be detected and explained to the user.
- No global keylogging is used.

### Exit criteria

Proceed only when Accessibility-based capture is stable enough for a limited prototype.

---

# Phase 1 — Controlled Text Capture

### Objective

Create the foundation for observing text changes safely in approved applications.

### Scope

Implement:

- Menu bar application shell.
- Accessibility permission onboarding.
- Application allowlist.
- Application blocklist.
- Active and paused states.
- Focused text-field detection.
- Current-paragraph extraction.
- Typing-pause detection.
- Temporary text snapshots.
- Secure-field blocking.
- Basic local session storage.

### User-facing features

- Start learning.
- Pause learning.
- See current application status.
- Approve or block applications.
- Review the currently captured paragraph.
- Delete today's temporary data.

### Deliverables

- Working menu bar prototype.
- Settings window.
- Privacy status indicator.
- Session and snapshot storage.
- Application compatibility logging without raw text.

### Acceptance criteria

- The app captures text only in approved applications.
- The app stops immediately when paused.
- The app never captures secure text fields.
- The app stores no raw keystrokes.
- The app creates a temporary paragraph snapshot after a typing pause.
- The app discards duplicate snapshots.
- The app deletes temporary data on user request.
- The menu bar always shows whether learning is active.

### Metrics

- Successful text-field detection rate.
- Snapshot duplication rate.
- Unsupported-field rate.
- Secure-field blocking accuracy.
- Average snapshot size.
- Percentage of sessions completed without errors.

---

# Phase 2 — Edit Detection and Correction Events

### Objective

Detect meaningful changes between earlier and later text versions.

### Scope

Implement:

- Text-difference engine.
- Sentence and paragraph segmentation.
- Changed-span extraction.
- Whitespace and punctuation normalization.
- Edit classification.
- Correction-event creation.
- Session finalization.
- Raw snapshot retention rules.

### Edit classifications

- Insertion.
- Deletion.
- Replacement.
- Word-order change.
- Punctuation correction.
- Capitalization correction.
- Grammar-related change.
- Style-related change.
- Vocabulary preference.
- Unknown.

### Deliverables

- Structured correction-event pipeline.
- Correction event viewer for internal testing.
- Diff quality test suite.
- Retention policy implementation.

### Acceptance criteria

- The app detects word replacements correctly in common cases.
- The app isolates the smallest useful changed fragment.
- Formatting-only changes are ignored where appropriate.
- Meaningful edits produce correction events.
- Unchanged text does not produce correction events.
- Old raw snapshots are deleted after events are extracted.
- The user can delete individual correction events.

### Metrics

- Precision of detected meaningful edits.
- False-event rate.
- Percentage of events with correct changed spans.
- Average retained raw-text duration.
- Percentage of sessions successfully converted into events.

---

# Phase 3 — Personal Pattern Learning

### Objective

Turn repeated correction events into a useful personal writing profile.

### Scope

Implement:

- Correction-event clustering.
- Pattern categories.
- Frequency and recency tracking.
- Confidence scoring.
- Conflict detection.
- Personal vocabulary extraction.
- Pattern enable and disable controls.
- Pattern review interface.

### Initial pattern categories

- Verb tense.
- Subject-verb agreement.
- Article usage.
- Preposition usage.
- Singular and plural agreement.
- Sentence fragments.
- Repeated words.
- Punctuation habits.
- Capitalization.
- Formality preference.
- Conciseness preference.
- Personal terminology.

### Deliverables

- Pattern database.
- Pattern clustering pipeline.
- Writing profile summary.
- Learned-pattern management screen.
- Personal vocabulary screen.

### Acceptance criteria

- Similar correction events are grouped into one pattern.
- A pattern is not activated until it reaches a minimum confidence threshold.
- Conflicting examples lower pattern confidence.
- Users can inspect examples supporting a pattern.
- Users can disable or delete a pattern.
- Repeated technical vocabulary becomes part of personal vocabulary.
- Raw text is minimized after pattern extraction.

### Metrics

- Number of correction events required to create a reliable pattern.
- Pattern merge accuracy.
- Pattern false-positive rate.
- Number of user-deleted patterns.
- Percentage of patterns with understandable explanations.

---

# Phase 4 — Local Grammar Analysis

### Objective

Provide grammar and style findings for the current sentence or paragraph.

### Scope

Implement:

- Local grammar engine integration.
- Sentence-level analysis.
- Structured issue output.
- Confidence scoring.
- Grammar explanations.
- Suggestion generation.
- Manual review shortcut.
- Suggestion preview.

### Suggestion output requirements

Each suggestion should include:

- Original text.
- Suggested replacement.
- Issue category.
- Explanation.
- Confidence.
- Text range.
- Whether it is personalized.
- Personalization reason.

### Deliverables

- Review-current-paragraph command.
- Suggestion list interface.
- Grammar explanations.
- Basic replacement workflow.
- Undo workflow.

### Acceptance criteria

- The user can review the current paragraph on demand.
- Suggestions identify the relevant text range.
- Suggestions include a readable explanation.
- The app never changes text without approval.
- Every accepted change can be undone.
- Grammar analysis continues to work without internet access.
- Unsupported fields fail safely.

### Metrics

- Suggestion precision.
- Suggestion acceptance rate.
- Undo rate.
- Analysis latency.
- Crash-free review sessions.
- Percentage of suggestions with valid text ranges.

---

# Phase 5 — Personalized Suggestion Ranking

### Objective

Use learned patterns and preferences to improve suggestion relevance.

### Scope

Implement:

- Retrieval of relevant personal patterns.
- Personalized suggestion ranking.
- Rejection-based suppression.
- Application-specific preferences.
- Tone preference weighting.
- Personal vocabulary protection.
- Personalized explanation generation.

### Example personalization explanation

> You made a similar tense correction six times in the past month.

### Deliverables

- Personalization engine.
- Suggestion-ranking logic.
- "Why this suggestion?" interface.
- Accept, reject, edit, and ignore feedback capture.
- Pattern-confidence update pipeline.

### Acceptance criteria

- Relevant personal patterns increase suggestion priority.
- Repeatedly rejected suggestions are shown less often.
- Personal vocabulary is not repeatedly flagged.
- Users can see why a suggestion is personalized.
- Accept and reject actions update the writing profile.
- The user can reset personalization without deleting application settings.

### Metrics

- Personalized suggestion acceptance rate.
- Difference between generic and personalized acceptance rates.
- Repeated-rejection suppression rate.
- Percentage of suggestions with a clear personalization reason.
- User-reported usefulness of personalization.

---

# Phase 6 — Insights and User Control

### Objective

Help users understand their writing habits and manage what the app has learned.

### Scope

Implement:

- Writing insights dashboard.
- Common grammar-pattern report.
- Improvement-over-time report.
- Accepted and rejected suggestion counts.
- Recent learning events.
- Personal vocabulary management.
- Data retention settings.
- Data export.
- Full data deletion.

### Deliverables

- Insights dashboard.
- Pattern history.
- Privacy and data management center.
- Local export format.
- Reset and deletion workflows.

### Acceptance criteria

- Users can see their most frequent patterns.
- Users can view supporting examples.
- Users can remove individual patterns.
- Users can export their writing profile.
- Users can delete all stored data.
- Deletion removes local raw text, events, patterns, and preferences.
- The dashboard never exposes text from blocked applications.

### Metrics

- Dashboard usage.
- Pattern-removal frequency.
- Export completion rate.
- Data-deletion success rate.
- Improvement trend engagement.
- User comprehension of learned patterns.

---

# Phase 7 — Reliability, Privacy Review, and Beta

### Objective

Prepare the product for external testing.

### Scope

Implement:

- Compatibility testing.
- Performance optimization.
- Accessibility-permission recovery.
- Crash reporting without raw text.
- Privacy review.
- Security review.
- Beta feedback collection.
- Onboarding improvements.
- Data migration and database recovery.

### Beta target

A small private beta with users who:

- Write frequently in English.
- Use Apple Notes, Mail, TextEdit, Safari, or Chrome.
- Understand that the product is experimental.
- Agree to provide structured feedback.

### Deliverables

- Beta-ready application build.
- Privacy documentation.
- Security review report.
- Compatibility matrix.
- Feedback survey.
- Known limitations list.
- Support and troubleshooting guide.

### Acceptance criteria

- No raw user text appears in logs.
- Secure fields remain blocked across supported applications.
- The app recovers after Accessibility permission changes.
- The app handles unsupported editors without crashing.
- Core workflows have acceptable latency.
- Users can understand when the app is active.
- Users can fully delete their data.

### Metrics

- Crash-free session rate.
- Permission-related failure rate.
- Secure-field incident count.
- Suggestion latency.
- Weekly active beta users.
- User trust rating.
- User-reported recommendation quality.
- Percentage of users who keep learning enabled after one week.

---

# Phase 8 — Optional Cloud Intelligence

### Objective

Add advanced language analysis only after local functionality and trust are established.

### Preconditions

Do not begin this phase until:

- Local capture is reliable.
- Privacy controls are complete.
- The app has a clear consent model.
- Users can use the core product without cloud processing.
- Data minimization has been reviewed.

### Scope

Potential features:

- Advanced rewriting.
- Better contextual grammar explanations.
- Tone transformation.
- Longer-document analysis.
- Semantic similarity for pattern retrieval.
- Optional model-assisted pattern classification.

### Privacy requirements

- Cloud processing must be opt-in.
- The exact text being sent must be visible to the user.
- Only the minimum required text should be sent.
- Sensitive applications must remain blocked.
- Cloud text should not be retained by default.
- The user must be able to disable cloud features at any time.
- Local-only mode must remain fully functional.

### Acceptance criteria

- No text is sent without explicit opt-in.
- The app clearly indicates when cloud analysis is used.
- Local-only users retain core grammar and personalization features.
- Cloud requests exclude blocked and secure contexts.
- Users can inspect and delete cloud-related history stored locally.

---

## 12. Suggested Development Order

Recommended order:

1. Accessibility feasibility.
2. Secure-field detection.
3. Menu bar controls.
4. Application allowlist.
5. Paragraph snapshots.
6. Text-difference engine.
7. Correction events.
8. Pattern clustering.
9. Local grammar analysis.
10. Personalized ranking.
11. Insights dashboard.
12. Beta hardening.
13. Optional cloud intelligence.

Do not build advanced AI features before capture, privacy, and learning-event quality are reliable.

---

## 13. UX Requirements

### 13.1 Status clarity

The application must always make its state clear:

- Active.
- Paused.
- Blocked in this application.
- Unsupported field.
- Accessibility permission required.
- Secure field detected.

### 13.2 Suggestion interaction

Users must be able to:

- View the issue.
- View the explanation.
- View the personalized reason.
- Accept the suggestion.
- Reject the suggestion.
- Edit the suggestion.
- Ignore the suggestion.
- Undo an accepted change.

### 13.3 Trust-oriented language

Prefer:

- "Learning is active in Notes."
- "This field is blocked."
- "This suggestion is based on your previous edits."
- "Text is processed locally."

Avoid:

- "Monitoring everything you type."
- "Recording your keyboard."
- "Watching your activity."
- "Capturing all input."

---

## 14. Error Handling

The app must fail safely.

### Required behaviors

- If Accessibility access is unavailable, stop capture and explain how to restore access.
- If the focused field is unsupported, do not attempt repeated writes.
- If a text replacement fails, preserve the original text.
- If a range becomes stale, cancel the replacement and request a new review.
- If the database is unavailable, pause learning rather than losing data silently.
- If a secure field cannot be classified confidently, treat it as blocked.
- If a pattern has low confidence, do not present it as a definite rule.

---

## 15. Performance Requirements

Initial targets:

- Focused-field status update: under 300 ms.
- Snapshot capture after pause: under 500 ms.
- Paragraph diff generation: under 200 ms for normal messages.
- Local grammar review: under 2 seconds for one paragraph.
- Suggestion application: under 500 ms when the target range is valid.
- Menu bar interaction: immediate perceived response.
- Idle CPU usage: minimal.
- No continuous high-frequency polling where event-driven behavior is possible.

---

## 16. Accessibility Requirements

The application itself should:

- Support VoiceOver.
- Provide keyboard navigation.
- Use clear labels for all controls.
- Avoid color-only status indicators.
- Support increased text size.
- Provide accessible descriptions for suggestion categories.
- Keep menu bar actions available without a mouse.

---

## 17. Analytics Requirements

Product analytics must not contain raw user text.

Allowed analytics examples:

- Feature enabled.
- Suggestion shown.
- Suggestion accepted.
- Suggestion rejected.
- Application supported or unsupported.
- Review latency.
- Crash event.
- Permission state.
- Pattern category identifier.

Prohibited analytics examples:

- Full sentence content.
- Password-field content.
- Personal vocabulary entries.
- Original and final text.
- Clipboard content.
- Document names without explicit approval.

---

## 18. Risks and Mitigations

### Risk: The product feels like a keylogger

Mitigation:

- Never store raw keystrokes.
- Use visible status indicators.
- Require explicit application approval.
- Explain paragraph-snapshot behavior.
- Make pause and deletion easy.

### Risk: Accessibility support is inconsistent

Mitigation:

- Start with a limited compatibility list.
- Test applications individually.
- Fail safely in unsupported editors.
- Add browser extensions later for difficult browser editors if needed.

### Risk: Personal patterns are incorrect

Mitigation:

- Require repeated evidence.
- Use confidence thresholds.
- Show supporting examples.
- Let users disable and delete patterns.
- Reduce confidence after rejection.

### Risk: Too much raw text is retained

Mitigation:

- Use temporary snapshots.
- Extract structured correction events.
- Delete raw snapshots quickly.
- Offer configurable retention.
- Store summarized patterns instead of full documents.

### Risk: Suggestions interrupt the user

Mitigation:

- Start with manual review.
- Add passive suggestions later.
- Let users configure frequency.
- Avoid showing low-confidence findings.
- Support application-specific behavior.

### Risk: Text replacement corrupts content

Mitigation:

- Validate ranges before replacement.
- Keep an undo record.
- Cancel when the editor state changes.
- Require confirmation for multi-sentence replacements.

---

## 19. MVP Definition

The MVP includes Phases 0 through 5 with a minimal version of Phase 6.

The MVP must:

1. Run as a macOS menu bar app.
2. Request Accessibility permission.
3. Read a paragraph from supported approved applications.
4. Block secure and prohibited fields.
5. Capture temporary before-and-after snapshots.
6. Detect manual corrections.
7. Group repeated corrections into patterns.
8. Review the current paragraph locally.
9. Rank suggestions using learned patterns.
10. Explain why a suggestion is personalized.
11. Let the user accept, reject, edit, ignore, and undo.
12. Let the user pause learning.
13. Let the user delete all stored data.

---

## 20. MVP Success Criteria

The MVP is successful when:

- At least 90% of capture attempts in supported applications complete without crashing.
- Secure fields are blocked in all tested scenarios.
- Repeated correction patterns can be identified from real user edits.
- Personalized suggestions have a higher acceptance rate than generic suggestions.
- Users understand when learning is active.
- Users can remove incorrect learned patterns.
- Users can delete all local data successfully.
- No raw user text is present in diagnostic logs.
- At least 60% of beta users report that the app's suggestions become more relevant over time.

---

## 21. Open Questions

1. What minimum macOS version should be supported?
2. Which three applications are mandatory for the first prototype?
3. Should learning occur automatically after a pause or only after an explicit command?
4. How long should temporary snapshots be retained?
5. Which local grammar engine should be used initially?
6. Should application-specific writing profiles be enabled in the MVP?
7. How should private browser windows be detected reliably?
8. Should raw correction examples remain visible after patterns are extracted?
9. What confidence threshold should activate a learned pattern?
10. Should the first beta support languages other than English?
11. Should users be able to create separate work and personal profiles?
12. What export format should be supported first?

---

## 22. Recommended Prototype Scope

For the first working prototype, limit support to:

- TextEdit.
- Apple Notes.
- Apple Mail.

Include:

- Manual review shortcut.
- Paragraph snapshot after a typing pause.
- Local correction-event extraction.
- Basic pattern grouping.
- Simple personalized suggestion explanations.
- Menu bar pause control.
- Application allowlist.
- Secure-field blocking.
- Full local-data deletion.

Defer:

- Automatic inline underlines.
- Browser extension support.
- Cloud analysis.
- Multi-device sync.
- Long-document analysis.
- Team features.
- Full App Store distribution work.

---

## 23. Release Milestones

### Milestone A — Technical proof

- Accessibility capture works.
- Secure fields are blocked.
- Text replacement works in selected applications.

### Milestone B — Learning proof

- Before-and-after edits are detected.
- Repeated edits become patterns.
- Patterns can be inspected and deleted.

### Milestone C — Recommendation proof

- Current paragraph can be reviewed.
- Learned patterns affect ranking.
- Suggestions can be accepted and undone.

### Milestone D — Trust proof

- Application controls are clear.
- Raw text retention is minimized.
- Full data deletion works.
- Beta users understand when capture is active.

### Milestone E — Private beta

- Stable build.
- Privacy review complete.
- Compatibility matrix published.
- Feedback collection active.

---

## 24. Final Product Statement

The Personalized Writing Coach for macOS is a privacy-first assistant that learns from the user's final edits, recurring corrections, and explicit feedback.

It does not record every key. It observes limited text snapshots in approved applications, converts changes into reusable patterns, and uses those patterns to make future writing recommendations more relevant.
