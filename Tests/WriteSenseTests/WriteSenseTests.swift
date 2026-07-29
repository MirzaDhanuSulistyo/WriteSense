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
