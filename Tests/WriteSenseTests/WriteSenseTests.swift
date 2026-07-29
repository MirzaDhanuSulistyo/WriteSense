import XCTest
@testable import WriteSense

final class WriteSenseTests: XCTestCase {
    func testDiffExtractsAChangedWord() {
        let diff = TextDiffEngine().diff(
            before: "I already send the email yesterday.",
            after: "I already sent the email yesterday."
        )

        XCTAssertTrue(diff.isMeaningful)
        XCTAssertEqual(diff.before, "send")
        XCTAssertEqual(diff.after, "sent")
    }

    func testLocalEngineFindsOfflineGrammarSuggestions() {
        let result = LocalLanguageEngine().analyze(
            "She have a apple and already send it yesterday.",
            profile: .empty
        )

        XCTAssertTrue(result.suggestions.contains { $0.category == .agreement })
        XCTAssertTrue(result.suggestions.contains { $0.category == .articleUsage })
        XCTAssertTrue(result.suggestions.contains { $0.category == .verbTense })
    }

    func testCatchesSpellingArticleAndQuestionIssuesLocally() {
        let result = LocalLanguageEngine().analyze(
            "can yu give me example ,",
            profile: .empty,
            applicationBundleID: "com.apple.Terminal"
        )

        XCTAssertTrue(result.suggestions.contains { $0.category == .spelling && $0.suggestedText == "you" })
        XCTAssertTrue(result.suggestions.contains { $0.category == .capitalization && $0.suggestedText == "C" })
        XCTAssertTrue(result.suggestions.contains { $0.category == .articleUsage && $0.suggestedText == "an example" })
        XCTAssertTrue(result.suggestions.contains { $0.category == .punctuation && $0.suggestedText == "?" })
    }

    func testCapitalizationChecksCanBeDisabled() {
        let result = LocalLanguageEngine().analyze(
            "this sentence is otherwise correct.",
            profile: .empty,
            applicationBundleID: "com.apple.TextEdit",
            includeCapitalization: false
        )

        XCTAssertFalse(result.suggestions.contains { $0.category == .capitalization })
    }

    func testLegacySettingsEnableCapitalizationByDefault() throws {
        let data = #"{"approvedBundleIDs":["com.apple.TextEdit"],"learningEnabled":true}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(StoredSettings.self, from: data)

        XCTAssertTrue(settings.capitalizationChecksEnabled)
        XCTAssertTrue(settings.learningEnabled)
        XCTAssertFalse(settings.diagnosticsEnabled, "Legacy users must opt in to beta diagnostics")
    }

    func testLegacyProfileDecodesWithoutGeneralizationMetadata() throws {
        let patternID = UUID()
        let json = """
        {
          "patterns": [{
            "id": "\(patternID.uuidString)",
            "category": "verb_tense",
            "description": "Legacy pattern",
            "exampleBefore": "send",
            "exampleAfter": "sent",
            "occurrenceCount": 2,
            "acceptanceCount": 0,
            "rejectionCount": 0,
            "confidence": 0.59,
            "enabled": true,
            "lastObservedAt": "2026-07-29T12:00:00Z",
            "applicationBundleID": "com.apple.Notes"
          }],
          "vocabulary": [],
          "acceptedSuggestionCount": 0,
          "rejectedSuggestionCount": 0,
          "updatedAt": "2026-07-29T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(WritingProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.patterns.first?.id, patternID)
        XCTAssertNil(profile.patterns.first?.generalizedKey)
        XCTAssertNil(profile.vocabularySources)
        XCTAssertNil(profile.suggestionPreferences)
    }

    func testAmbiguousIncompleteQuestionRequestsClarification() {
        let result = LocalLanguageEngine().analyze(
            "how do me",
            profile: .empty,
            applicationBundleID: "com.apple.TextEdit"
        )

        XCTAssertEqual(result.suggestions.count, 1)
        XCTAssertEqual(result.suggestions[0].category, .clarity)
        XCTAssertTrue(result.suggestions[0].requiresClarification)
        XCTAssertEqual(result.suggestions[0].alternativeTexts, [
            "How do I do it?", "How about me?", "How can you help me?"
        ])
    }

    func testCatchesExactShortTerminalQuestion() {
        var profile = WritingProfile.empty
        profile.vocabulary.insert("yu") // A stale learned entry must not hide a known typo.
        let result = LocalLanguageEngine().analyze(
            "Can yu give example?",
            profile: profile,
            applicationBundleID: "com.apple.Terminal"
        )

        XCTAssertTrue(result.suggestions.contains { $0.category == .spelling && $0.suggestedText == "you" })
        XCTAssertTrue(result.suggestions.contains { $0.category == .articleUsage && $0.suggestedText == "an example" })
    }

    func testSupportedSentenceTypeRegressionMatrix() {
        let terminalCases: [(name: String, input: String, expected: String)] = [
            ("declarative", "She have a apple.", "She has an apple."),
            ("interrogative", "can yu give example ,", "Can you give an example?"),
            ("imperative", "Please give me example.", "Please give me an example."),
            ("exclamatory", "what a amazing idea!", "What an amazing idea!"),
            ("negative agreement", "He do not agree.", "He does not agree."),
            ("plural agreement", "They is ready.", "They are ready."),
            ("compound", "She have a report and he are ready.", "She has a report and he is ready."),
            ("third-person verb", "She only need me.", "She only needs me."),
            ("modal phrase", "We should of left.", "We should have left."),
            ("repeated word", "This is is useful.", "This is useful."),
            ("past marker before verb", "I already send the report.", "I already sent the report."),
            ("past marker after verb", "I send the report yesterday.", "I sent the report yesterday."),
            ("common spelling", "Teh adress is here.", "The address is here."),
            ("concision", "In order to improve, we revised it.", "To improve, we revised it.")
        ]

        for item in terminalCases {
            let analysis = LocalLanguageEngine().analyze(
                item.input,
                profile: .empty,
                applicationBundleID: "com.apple.Terminal"
            )
            XCTAssertEqual(applying(analysis.suggestions, to: item.input), item.expected, item.name)
        }

        let punctuationInput = "Hello  world ,"
        let punctuation = LocalLanguageEngine().analyze(
            punctuationInput,
            profile: .empty,
            applicationBundleID: "com.apple.TextEdit"
        )
        XCTAssertEqual(applying(punctuation.suggestions, to: punctuationInput), "Hello world,", "spacing and punctuation")
    }

    func testDeterministicFallbacksCoverKnownModelWeaknesses() {
        let cases: [(String, String)] = [
            ("Me and her went home.", "She and I went home."),
            ("This option is more better.", "This option is better."),
            ("She is good in mathematics.", "She is good at mathematics."),
            ("If I would know, I would tell you.", "If I knew, I would tell you."),
            ("In order to improve, we revised it.", "To improve, we revised it."),
            ("They is ready.", "They are ready."),
            ("She need more time.", "She needs more time.")
        ]

        for (input, expected) in cases {
            let analysis = LocalLanguageEngine().analyze(
                input,
                profile: .empty,
                applicationBundleID: "com.apple.Terminal"
            )
            XCTAssertEqual(applying(analysis.suggestions, to: input), expected, input)
        }
    }

    func testAllTwelveTenseFormsHaveDeterministicFallbacks() {
        let cases: [(String, String)] = [
            ("She go to work every day.", "She goes to work every day."),
            ("She are reading now.", "She is reading now."),
            ("She have finished the report.", "She has finished the report."),
            ("She have been working for two hours.", "She has been working for two hours."),
            ("She go to work yesterday.", "She went to work yesterday."),
            ("She were reading at noon.", "She was reading at noon."),
            ("She has finished before the meeting started.", "She had finished before the meeting started."),
            ("She has been working for two hours before lunch began.", "She had been working for two hours before lunch began."),
            ("She will goes tomorrow.", "She will go tomorrow."),
            ("She will be work at noon.", "She will be working at noon."),
            ("She will has finished by Friday.", "She will have finished by Friday."),
            ("By noon, she will have been work for two hours.", "By noon, she will have been working for two hours.")
        ]

        for (input, expected) in cases {
            let analysis = LocalLanguageEngine().analyze(
                input,
                profile: .empty,
                applicationBundleID: "com.apple.Terminal"
            )
            XCTAssertEqual(applying(analysis.suggestions, to: input), expected, input)
        }
    }

    func testRepeatedEditsBecomeReliablePatterns() {
        var profile = WritingProfile.empty
        let learner = PatternLearner()
        let diff = CorrectionDiff(before: "send", after: "sent", isMeaningful: true)

        learner.learn(from: diff, in: "I send it yesterday.", fullAfter: "I sent it yesterday.", profile: &profile, applicationBundleID: "com.apple.Notes")
        learner.learn(from: diff, in: "I send it yesterday.", fullAfter: "I sent it yesterday.", profile: &profile, applicationBundleID: "com.apple.Notes")

        XCTAssertEqual(profile.patterns.count, 1)
        XCTAssertTrue(profile.patterns[0].isReliable)
    }

    func testDiffProducesSeparateStructuredEdits() {
        let diffs = TextDiffEngine().diffs(
            before: "She have a apple and I send it yesterday.",
            after: "She has an apple and I sent it yesterday."
        )

        XCTAssertEqual(diffs.map(\.before), ["have", "a", "send"])
        XCTAssertEqual(diffs.map(\.after), ["has", "an", "sent"])
        XCTAssertTrue(diffs.allSatisfy(\.isMeaningful))
    }

    func testLongParagraphDiffUsesBoundedFallback() {
        let prefix = Array(repeating: "word", count: 550).joined(separator: " ")
        let suffix = Array(repeating: "tail", count: 20).joined(separator: " ")
        let before = "\(prefix) old \(suffix)"
        let after = "\(prefix) new \(suffix)"

        let diff = TextDiffEngine().diff(before: before, after: after)
        XCTAssertTrue(diff.isMeaningful)
        XCTAssertEqual(diff.before, "old")
        XCTAssertEqual(diff.after, "new")
    }

    func testDiffClassifiesWordOrderAndIgnoresWhitespaceOnlyChanges() {
        let reordered = TextDiffEngine().diff(
            before: "Please write clearly now.",
            after: "Please clearly write now."
        )
        XCTAssertEqual(reordered.before, "write clearly")
        XCTAssertEqual(reordered.after, "clearly write")
        XCTAssertEqual(reordered.classification, .wordOrder)

        let whitespace = TextDiffEngine().diffs(
            before: "Hello  world.",
            after: "Hello world."
        )
        XCTAssertTrue(whitespace.isEmpty)
    }

    func testInsertedArticleBecomesArticlePatternInsteadOfVocabulary() {
        let diff = TextDiffEngine().diff(
            before: "Please give example.",
            after: "Please give an example."
        )
        XCTAssertEqual(diff.before, "")
        XCTAssertEqual(diff.after, "an")
        XCTAssertEqual(diff.classification, .insertion)

        var profile = WritingProfile.empty
        let event = PatternLearner().learn(
            from: diff,
            in: "Please give example.",
            fullAfter: "Please give an example.",
            profile: &profile,
            applicationBundleID: "com.apple.Notes"
        )
        XCTAssertEqual(event?.category, .articleUsage)
        XCTAssertTrue(profile.vocabulary.isEmpty)
    }

    func testGeneralizedTensePatternPersonalizesAnotherVerb() {
        var profile = WritingProfile.empty
        let learner = PatternLearner()
        learner.learn(
            from: CorrectionDiff(before: "send", after: "sent", isMeaningful: true),
            in: "I send it yesterday.",
            fullAfter: "I sent it yesterday.",
            profile: &profile,
            applicationBundleID: "com.apple.Notes"
        )
        learner.learn(
            from: CorrectionDiff(before: "go", after: "went", isMeaningful: true),
            in: "I go yesterday.",
            fullAfter: "I went yesterday.",
            profile: &profile,
            applicationBundleID: "com.apple.Notes"
        )

        XCTAssertEqual(profile.patterns.count, 1)
        XCTAssertTrue(profile.patterns[0].isReliable)
        XCTAssertEqual(profile.patterns[0].allExamples.count, 2)

        let suggestion = Suggestion(
            originalText: "write",
            suggestedText: "wrote",
            category: .verbTense,
            explanation: "Use past tense.",
            confidence: 0.8,
            range: TextRange(location: 2, length: 5)
        )
        let inNotes = PersonalizationEngine().rank(
            [suggestion],
            using: profile,
            applicationBundleID: "com.apple.Notes"
        )
        XCTAssertTrue(inNotes[0].isPersonalized)
        XCTAssertEqual(inNotes[0].patternID, profile.patterns[0].id)

        let inSafari = PersonalizationEngine().rank(
            [suggestion],
            using: profile,
            applicationBundleID: "com.apple.Safari"
        )
        XCTAssertFalse(inSafari[0].isPersonalized, "Single-app patterns should stay scoped to that app")
    }

    func testRepeatedGenericRejectionsAreSuppressedPerApplication() {
        var profile = WritingProfile.empty
        let learner = PatternLearner()
        let suggestion = Suggestion(
            originalText: "have",
            suggestedText: "has",
            category: .agreement,
            explanation: "Match the singular subject.",
            confidence: 0.85,
            range: TextRange(location: 4, length: 4)
        )

        for _ in 0..<3 {
            learner.record(
                outcome: .rejected,
                for: suggestion,
                profile: &profile,
                applicationBundleID: "com.apple.Notes"
            )
        }

        XCTAssertTrue(PersonalizationEngine().rank(
            [suggestion],
            using: profile,
            applicationBundleID: "com.apple.Notes"
        ).isEmpty)
        XCTAssertEqual(PersonalizationEngine().rank(
            [suggestion],
            using: profile,
            applicationBundleID: "com.apple.Mail"
        ).count, 1)
    }

    func testLargeRewritesAreNotRetainedAsPatterns() {
        var profile = WritingProfile.empty
        let longText = String(repeating: "sensitive ", count: 40)
        let event = PatternLearner().learn(
            from: CorrectionDiff(before: "", after: longText, isMeaningful: true, classification: .insertion),
            in: "",
            fullAfter: longText,
            profile: &profile,
            applicationBundleID: "com.apple.Notes"
        )

        XCTAssertNil(event)
        XCTAssertTrue(profile.patterns.isEmpty)
    }

    func testLearningReturnsMinimalCorrectionEvent() {
        var profile = WritingProfile.empty
        let sessionID = UUID()
        let event = PatternLearner().learn(
            from: CorrectionDiff(
                before: "have",
                after: "has",
                isMeaningful: true,
                classification: .replacement
            ),
            in: "She have an answer.",
            fullAfter: "She has an answer.",
            profile: &profile,
            applicationBundleID: "com.apple.Notes",
            applicationName: "Notes",
            sessionID: sessionID
        )

        XCTAssertEqual(event?.sessionID, sessionID)
        XCTAssertEqual(event?.changedFragmentBefore, "have")
        XCTAssertEqual(event?.changedFragmentAfter, "has")
        XCTAssertEqual(event?.classification, .grammar)
        XCTAssertEqual(event?.category, .agreement)
        XCTAssertNotNil(event?.patternID)
    }

    func testHistoryRetentionPrunesTextBearingAndMetadataEvents() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseRetention-\(UUID().uuidString)")
        let service = "com.writesense.tests.\(UUID().uuidString)"
        let store = ProfileStore(directoryURL: directory, keychainService: service)
        defer { store.deleteAllData() }

        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -31, to: now)!
        let recent = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let history = WritingHistory(
            correctionEvents: [
                correctionEvent(at: old),
                correctionEvent(at: recent)
            ],
            suggestionEvents: [
                SuggestionFeedbackEvent(
                    category: .agreement,
                    outcome: .accepted,
                    wasPersonalized: true,
                    patternID: nil,
                    applicationBundleID: "com.apple.Notes",
                    createdAt: old
                ),
                SuggestionFeedbackEvent(
                    category: .agreement,
                    outcome: .rejected,
                    wasPersonalized: false,
                    patternID: nil,
                    applicationBundleID: "com.apple.Notes",
                    createdAt: recent
                )
            ],
            editingSessions: [
                EditingSessionRecord(
                    id: UUID(),
                    applicationName: "Notes",
                    applicationBundleID: "com.apple.Notes",
                    startedAt: old,
                    lastUpdatedAt: old
                ),
                EditingSessionRecord(
                    id: UUID(),
                    applicationName: "Notes",
                    applicationBundleID: "com.apple.Notes",
                    startedAt: recent,
                    lastUpdatedAt: recent
                )
            ],
            privacyAuditEvents: [
                PrivacyAuditEvent(action: .learningEnabled, createdAt: old),
                PrivacyAuditEvent(action: .learningDisabled, createdAt: recent)
            ]
        )

        let pruned = store.pruned(history: history, retentionDays: 30, now: now)
        XCTAssertEqual(pruned.correctionEvents.map(\.createdAt), [recent])
        XCTAssertEqual(pruned.suggestionEvents.map(\.createdAt), [recent])
        XCTAssertEqual(pruned.editingSessions?.map(\.lastUpdatedAt), [recent])
        XCTAssertEqual(pruned.privacyAuditEvents?.map(\.createdAt), [recent])
        XCTAssertEqual(store.pruned(history: history, retentionDays: 0), .empty)
    }

    func testDiagnosticExportCannotIncludeRetainedWritingFragments() throws {
        let history = WritingHistory(
            correctionEvents: [
                CorrectionEvent(
                    sessionID: UUID(),
                    applicationName: "Notes",
                    applicationBundleID: "com.apple.Notes",
                    changedFragmentBefore: "ULTRA_SECRET_ORIGINAL",
                    changedFragmentAfter: "ULTRA_SECRET_REPLACEMENT",
                    classification: .replacement,
                    category: .vocabulary
                )
            ],
            diagnosticEvents: [
                DiagnosticEvent(
                    operation: .textReplacement,
                    succeeded: false,
                    applicationBundleID: "com.apple.Notes",
                    errorCode: .staleOrUnsupportedRange
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(DiagnosticsExport.make(from: history))

        XCTAssertNil(data.range(of: Data("ULTRA_SECRET_ORIGINAL".utf8)))
        XCTAssertNil(data.range(of: Data("ULTRA_SECRET_REPLACEMENT".utf8)))
        XCTAssertNotNil(data.range(of: Data("stale_or_unsupported_range".utf8)))
    }

    func testDiagnosticsSummaryUsesOnlyContentFreeOperationalEvents() {
        let now = Date()
        let history = WritingHistory(
            suggestionEvents: [
                SuggestionFeedbackEvent(
                    category: .agreement,
                    outcome: .accepted,
                    wasPersonalized: true,
                    patternID: nil,
                    applicationBundleID: "com.apple.Notes",
                    createdAt: now
                ),
                SuggestionFeedbackEvent(
                    category: .agreement,
                    outcome: .rejected,
                    wasPersonalized: false,
                    patternID: nil,
                    applicationBundleID: "com.apple.Notes",
                    createdAt: now
                )
            ],
            editingSessions: [
                EditingSessionRecord(
                    id: UUID(),
                    applicationName: "Notes",
                    applicationBundleID: "com.apple.Notes",
                    startedAt: now,
                    lastUpdatedAt: now
                )
            ],
            privacyAuditEvents: [
                PrivacyAuditEvent(action: .secureFieldBlocked, applicationBundleID: "com.apple.Notes")
            ],
            diagnosticEvents: [
                DiagnosticEvent(operation: .localReview, succeeded: true, durationMilliseconds: 100),
                DiagnosticEvent(operation: .localReview, succeeded: true, durationMilliseconds: 300),
                DiagnosticEvent(operation: .textReplacement, succeeded: false),
                DiagnosticEvent(operation: .permissionUnavailable, succeeded: false)
            ],
            compatibilityObservations: [
                CompatibilityObservation(
                    applicationName: "Notes",
                    applicationBundleID: "com.apple.Notes",
                    result: .readWrite
                )
            ],
            applicationRuns: [
                ApplicationRunRecord(id: UUID(), startedAt: now, endedAt: now, cleanExit: true),
                ApplicationRunRecord(id: UUID(), startedAt: now, endedAt: now, cleanExit: false)
            ]
        )

        let summary = DiagnosticsSummary.make(from: history, now: now)
        XCTAssertEqual(summary.completedRunCount, 2)
        XCTAssertEqual(summary.uncleanRunCount, 1)
        XCTAssertEqual(summary.crashFreeRunRate, 0.5)
        XCTAssertEqual(summary.averageLocalReviewMilliseconds, 200)
        XCTAssertEqual(summary.p95LocalReviewMilliseconds, 300)
        XCTAssertEqual(summary.replacementFailureCount, 1)
        XCTAssertEqual(summary.permissionFailureCount, 1)
        XCTAssertEqual(summary.secureContextBlockCount, 1)
        XCTAssertEqual(summary.compatibilityCheckCount, 1)
        XCTAssertEqual(summary.weeklyActiveDays, 1)
        XCTAssertEqual(summary.retainedSuggestionAcceptanceRate, 0.5)
    }

    func testZeroActivityRetentionPreservesEnabledBetaDiagnostics() {
        let now = Date()
        let history = WritingHistory(
            correctionEvents: [correctionEvent(at: now)],
            diagnosticEvents: [
                DiagnosticEvent(operation: .localReview, succeeded: true, createdAt: now)
            ],
            compatibilityObservations: [
                CompatibilityObservation(
                    applicationName: "Notes",
                    applicationBundleID: "com.apple.Notes",
                    result: .readWrite,
                    createdAt: now
                )
            ]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseDiagnosticRetention-\(UUID().uuidString)")
        let store = ProfileStore(
            directoryURL: directory,
            keychainService: "com.writesense.tests.\(UUID().uuidString)"
        )
        defer { store.deleteAllData() }

        let pruned = store.pruned(history: history, retentionDays: 0, now: now)
        XCTAssertTrue(pruned.correctionEvents.isEmpty)
        XCTAssertEqual(pruned.diagnosticEvents?.count, 1)
        XCTAssertEqual(pruned.compatibilityObservations?.count, 1)
    }

    func testPlaintextPrototypeProfileMigratesToEncryptedStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = "com.writesense.tests.\(UUID().uuidString)"
        let legacyURL = directory.appendingPathComponent("writing-profile.json")
        var legacyProfile = WritingProfile.empty
        legacyProfile.vocabulary.insert("legacyterm")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacyProfile).write(to: legacyURL)

        let store = ProfileStore(directoryURL: directory, keychainService: service)
        defer { store.deleteAllData() }
        let migrated = store.loadProfile()

        XCTAssertEqual(migrated.vocabulary, Set(["legacyterm"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("writing-profile.enc").path
        ))
    }

    func testEncryptedBackupRecoversLastKnownGoodProfile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseRecovery-\(UUID().uuidString)")
        let service = "com.writesense.tests.\(UUID().uuidString)"
        let store = ProfileStore(directoryURL: directory, keychainService: service)

        var first = WritingProfile.empty
        first.vocabulary = ["first"]
        XCTAssertTrue(store.save(profile: first))
        var second = WritingProfile.empty
        second.vocabulary = ["second"]
        XCTAssertTrue(store.save(profile: second))

        let primary = directory.appendingPathComponent("writing-profile.enc")
        try Data("corrupted-primary".utf8).write(to: primary, options: [.atomic])

        let recoveringStore = ProfileStore(directoryURL: directory, keychainService: service)
        defer { recoveringStore.deleteAllData() }
        let recovered = recoveringStore.loadProfile()

        XCTAssertEqual(recovered.vocabulary, Set(["first"]))
        XCTAssertFalse(recoveringStore.hasLoadFailure)
        XCTAssertNotNil(recoveringStore.lastRecoveryMessage)
        XCTAssertTrue(recoveringStore.recoveredFileNames.contains("writing-profile.enc"))
    }

    @MainActor
    func testRecoveredSettingsFailClosedBeforeAppModelStarts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseSettingsRecovery-\(UUID().uuidString)")
        let service = "com.writesense.tests.\(UUID().uuidString)"
        let store = ProfileStore(directoryURL: directory, keychainService: service)
        let risky = StoredSettings(
            approvedBundleIDs: ["com.apple.Terminal"],
            learningEnabled: true,
            diagnosticsEnabled: true
        )
        XCTAssertTrue(store.save(settings: risky))
        var second = risky
        second.capitalizationChecksEnabled = false
        XCTAssertTrue(store.save(settings: second))
        try Data("corrupt-settings".utf8).write(
            to: directory.appendingPathComponent("settings.enc"),
            options: [.atomic]
        )

        let recoveringStore = ProfileStore(directoryURL: directory, keychainService: service)
        defer { recoveringStore.deleteAllData() }
        let model = AppModel(store: recoveringStore)

        XCTAssertFalse(model.isLearningActive)
        XCTAssertFalse(model.diagnosticsEnabled)
        XCTAssertFalse(model.onboardingCompleted)
        XCTAssertTrue(model.approvedApplications.isEmpty)
        XCTAssertTrue(model.storageAvailable)
    }

    func testRunMarkerDetectsUncleanAndCleanTermination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseRunMarker-\(UUID().uuidString)")
        let service = "com.writesense.tests.\(UUID().uuidString)"
        let store = ProfileStore(directoryURL: directory, keychainService: service)
        defer { store.deleteAllData() }
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        let first = try XCTUnwrap(store.beginApplicationRun(now: firstDate))
        XCTAssertNil(first.previousUnclean)
        let second = try XCTUnwrap(store.beginApplicationRun(now: secondDate))
        XCTAssertEqual(second.previousUnclean, first.current)

        store.finishApplicationRun(second.current.id)
        let third = try XCTUnwrap(store.beginApplicationRun(now: Date(timeIntervalSince1970: 300)))
        XCTAssertNil(third.previousUnclean)
        store.finishApplicationRun(third.current.id)
    }

    func testUnreadableEncryptedStorageFailsClosedUntilDeletion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseCorrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-an-aes-envelope".utf8).write(
            to: directory.appendingPathComponent("writing-profile.enc")
        )
        let store = ProfileStore(
            directoryURL: directory,
            keychainService: "com.writesense.tests.\(UUID().uuidString)"
        )

        XCTAssertTrue(store.loadProfile().patterns.isEmpty)
        XCTAssertTrue(store.hasLoadFailure)
        XCTAssertFalse(store.save(profile: .empty), "Unreadable data must not be overwritten silently")
        XCTAssertTrue(store.deleteAllData())
        XCTAssertFalse(store.hasLoadFailure)
    }

    func testProfileStoreEncryptsRoundTripsExportsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WriteSenseEncryption-\(UUID().uuidString)")
        let service = "com.writesense.tests.\(UUID().uuidString)"
        let store = ProfileStore(directoryURL: directory, keychainService: service)
        defer { store.deleteAllData() }

        var profile = WritingProfile.empty
        profile.vocabulary.insert("confidentialterm")
        XCTAssertTrue(store.save(profile: profile))

        let encryptedURL = directory.appendingPathComponent("writing-profile.enc")
        let ciphertext = try Data(contentsOf: encryptedURL)
        XCTAssertNil(ciphertext.range(of: Data("confidentialterm".utf8)))
        XCTAssertEqual(store.loadProfile().vocabulary, Set(["confidentialterm"]))

        let exportData = try store.exportData(
            profile: profile,
            history: .empty,
            settings: .defaults
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(WriteSenseExport.self, from: exportData)
        XCTAssertEqual(export.formatVersion, 2)
        XCTAssertEqual(export.profile.vocabulary, Set(["confidentialterm"]))

        XCTAssertTrue(store.deleteAllData())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func correctionEvent(at date: Date) -> CorrectionEvent {
        CorrectionEvent(
            sessionID: UUID(),
            applicationName: "Notes",
            applicationBundleID: "com.apple.Notes",
            changedFragmentBefore: "have",
            changedFragmentAfter: "has",
            classification: .grammar,
            category: .agreement,
            createdAt: date
        )
    }

    private func applying(_ suggestions: [Suggestion], to text: String) -> String {
        let result = NSMutableString(string: text)
        let descending = suggestions.sorted {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location > $1.range.location
        }
        for suggestion in descending {
            let range = suggestion.range.nsRange
            guard range.location != NSNotFound, NSMaxRange(range) <= result.length else { continue }
            result.replaceCharacters(in: range, with: suggestion.suggestedText)
        }
        return result as String
    }
}
