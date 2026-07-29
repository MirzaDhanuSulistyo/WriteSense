import AppKit
import Foundation
import NaturalLanguage

struct LanguageAnalysis {
    let language: String
    let suggestions: [Suggestion]
}

/// Offline language analysis for the first WriteSense prototype.
/// NaturalLanguage supplies token and language context; the deterministic rules
/// keep the MVP private, fast, and usable without a model download.
final class LocalLanguageEngine {
    func analyze(
        _ text: String,
        profile: WritingProfile,
        applicationBundleID: String? = nil,
        includeCapitalization: Bool = true,
        tonePreference: TonePreference = .preserveVoice
    ) -> LanguageAnalysis {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LanguageAnalysis(language: "Unknown", suggestions: [])
        }

        let language = languageName(for: text)
        let isTerminal = applicationBundleID == "com.apple.Terminal"
        var findings: [Suggestion] = []
        findings.append(contentsOf: spellingFindings(in: text, profile: profile, conservative: isTerminal))
        findings.append(contentsOf: structuralQuestionFindings(in: text))
        findings.append(contentsOf: systemGrammarFindings(in: text))
        if includeCapitalization {
            findings.append(contentsOf: capitalizationFindings(in: text))
        }
        findings.append(contentsOf: repeatedWordFindings(in: text))
        findings.append(contentsOf: pronounFindings(in: text))
        findings.append(contentsOf: phraseFindings(in: text))
        findings.append(contentsOf: agreementFindings(in: text))
        findings.append(contentsOf: tenseFindings(in: text))
        findings.append(contentsOf: articleFindings(in: text))
        findings.append(contentsOf: questionEndingFindings(in: text))
        findings.append(contentsOf: punctuationFindings(in: text))

        var unique = removeOverlappingFindings(findings)
        if isTerminal {
            // Terminal exposes shell formatting in its rendered screen buffer.
            // Keep prose checks, but suppress whitespace-only style findings.
            unique = unique.filter { suggestion in
                if suggestion.category != .punctuation { return true }
                return suggestion.originalText.contains(",") || suggestion.suggestedText == "?"
            }
        }
        let personalized = PersonalizationEngine().rank(
            unique,
            using: profile,
            applicationBundleID: applicationBundleID,
            tonePreference: tonePreference
        )
        return LanguageAnalysis(language: language, suggestions: personalized)
    }

    private func languageName(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return "English" }
        return Locale.current.localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
    }

    private func spellingFindings(in text: String, profile: WritingProfile, conservative: Bool) -> [Suggestion] {
        let commonCorrections: [String: String] = [
            "yu": "you", "teh": "the", "recieve": "receive", "seperate": "separate",
            "definately": "definitely", "adress": "address", "wich": "which", "becuase": "because"
        ]
        let source = text as NSString
        let tokenRegex = try! NSRegularExpression(pattern: #"\b[A-Za-z][A-Za-z'-]*\b"#)
        let tokens = tokenRegex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var findings: [Suggestion] = []

        for token in tokens {
            let word = source.substring(with: token.range)
            let normalized = word.lowercased()
            // High-confidence known typos must not be hidden by an accidentally
            // learned vocabulary entry (for example, Terminal screen output).
            guard let correction = commonCorrections[normalized] else { continue }
            findings.append(Suggestion(
                originalText: word,
                suggestedText: preserveCase(correction, like: word),
                category: .spelling,
                explanation: "Correct the spelling of ‘\(word).’",
                confidence: 0.99,
                range: TextRange(location: token.range.location, length: token.range.length)
            ))
        }

        // In Terminal, use only the conservative typo map to avoid flagging
        // command names, paths, environment variables, and program output.
        guard !conservative else { return findings }

        let checker = NSSpellChecker.shared
        var searchLocation = 0
        while searchLocation < source.length {
            var wordCount = 0
            let misspelled = checker.checkSpelling(
                of: text,
                startingAt: searchLocation,
                language: "en_US",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            guard misspelled.location != NSNotFound else { break }
            let word = source.substring(with: misspelled)
            let normalized = word.lowercased()
            if !profile.vocabulary.contains(normalized), commonCorrections[normalized] == nil,
               let guess = checker.guesses(
                    forWordRange: misspelled,
                    in: text,
                    language: "en_US",
                    inSpellDocumentWithTag: 0
               )?.first,
               !guess.isEmpty {
                findings.append(Suggestion(
                    originalText: word,
                    suggestedText: preserveCase(guess, like: word),
                    category: .spelling,
                    explanation: "This word may be misspelled.",
                    confidence: 0.76,
                    range: TextRange(location: misspelled.location, length: misspelled.length)
                ))
            }
            searchLocation = max(searchLocation + 1, NSMaxRange(misspelled))
        }
        return findings
    }

    private func structuralQuestionFindings(in text: String) -> [Suggestion] {
        let regex = try! NSRegularExpression(
            pattern: #"^\s*how\s+do\s+(me|him|her|us|them)\s*[?.!]?\s*$"#,
            options: [.caseInsensitive]
        )
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange),
              match.numberOfRanges > 1 else { return [] }

        let object = (text as NSString).substring(with: match.range(at: 1)).lowercased()
        let alternatives: [String]
        switch object {
        case "me":
            alternatives = ["How do I do it?", "How about me?", "How can you help me?"]
        case "him":
            alternatives = ["How does he do it?", "How do you know him?", "How can you help him?"]
        case "her":
            alternatives = ["How does she do it?", "How do you know her?", "How can you help her?"]
        case "us":
            alternatives = ["How do we do it?", "How about us?", "How can you help us?"]
        default:
            alternatives = ["How do they do it?", "How do you know them?", "How can you help them?"]
        }

        return [Suggestion(
            originalText: text,
            suggestedText: alternatives[0],
            category: .clarity,
            explanation: "This question is structurally incomplete and its intended meaning is ambiguous. Choose the meaning you intended.",
            confidence: 0.995,
            range: TextRange(location: 0, length: (text as NSString).length),
            alternativeTexts: alternatives
        )]
    }

    private func systemGrammarFindings(in text: String) -> [Suggestion] {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        let results = NSSpellChecker.shared.check(
            text,
            range: range,
            types: NSTextCheckingResult.CheckingType.grammar.rawValue,
            options: [:],
            inSpellDocumentWithTag: 0,
            orthography: nil,
            wordCount: nil
        )

        var findings: [Suggestion] = []
        for result in results {
            guard let details = result.grammarDetails else { continue }
            for detail in details {
                guard let localRange = (detail[NSGrammarRange] as? NSValue)?.rangeValue,
                      let corrections = detail[NSGrammarCorrections] as? [String],
                      let correction = corrections.first else { continue }
                let issueRange = NSRange(
                    location: result.range.location + localRange.location,
                    length: localRange.length
                )
                guard issueRange.location != NSNotFound,
                      NSMaxRange(issueRange) <= source.length else { continue }
                let original = source.substring(with: issueRange)
                let explanation = detail[NSGrammarUserDescription] as? String ?? "Review this grammar issue."
                let confidence = (detail["NSGrammarConfidenceScore"] as? NSNumber)?.doubleValue ?? 0.86
                findings.append(Suggestion(
                    originalText: original,
                    suggestedText: preserveCase(correction, like: original),
                    category: grammarCategory(original: original, correction: correction, explanation: explanation),
                    explanation: explanation,
                    confidence: min(0.97, max(0.7, confidence)),
                    range: TextRange(location: issueRange.location, length: issueRange.length)
                ))
            }
        }
        return findings
    }

    private func grammarCategory(original: String, correction: String, explanation: String) -> PatternCategory {
        let detail = explanation.lowercased()
        if detail.contains("agree") { return .agreement }
        if detail.contains("tense") { return .verbTense }
        if ["a", "an", "the"].contains(correction.lowercased()) { return .articleUsage }
        if original.rangeOfCharacter(from: .punctuationCharacters) != nil { return .punctuation }
        return .style
    }

    private func capitalizationFindings(in text: String) -> [Suggestion] {
        let regex = try! NSRegularExpression(pattern: #"(?m)(?:^|[.!?]\s+)([a-z])"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            let letter = (text as NSString).substring(with: range)
            return Suggestion(
                originalText: letter,
                suggestedText: letter.uppercased(),
                category: .capitalization,
                explanation: "Capitalize the first word of the sentence.",
                confidence: 0.96,
                range: TextRange(location: range.location, length: range.length)
            )
        }
    }

    private func repeatedWordFindings(in text: String) -> [Suggestion] {
        let regex = try! NSRegularExpression(pattern: #"\b([A-Za-z][A-Za-z'-]*)\s+\1\b"#, options: [.caseInsensitive])
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let fullRange = match.range(at: 0)
            let word = (text as NSString).substring(with: match.range(at: 1))
            return Suggestion(
                originalText: (text as NSString).substring(with: fullRange),
                suggestedText: word,
                category: .repeatedWords,
                explanation: "Remove the repeated word to make the sentence cleaner.",
                confidence: 0.94,
                range: TextRange(location: fullRange.location, length: fullRange.length)
            )
        }
    }

    private func pronounFindings(in text: String) -> [Suggestion] {
        let regex = try! NSRegularExpression(
            pattern: #"^(\s*)me\s+and\s+(him|her|them)\b"#,
            options: [.caseInsensitive]
        )
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 2 else { return [] }
        let source = text as NSString
        let leading = source.substring(with: match.range(at: 1))
        let second = source.substring(with: match.range(at: 2)).lowercased()
        let subject = ["him": "He", "her": "She", "them": "They"][second] ?? second.capitalized
        return [Suggestion(
            originalText: source.substring(with: match.range),
            suggestedText: "\(leading)\(subject) and I",
            category: .agreement,
            explanation: "Use subject pronouns for a compound sentence subject.",
            confidence: 0.93,
            range: TextRange(location: match.range.location, length: match.range.length)
        )]
    }

    private func phraseFindings(in text: String) -> [Suggestion] {
        var findings: [Suggestion] = []
        findings.append(contentsOf: replacing(
            pattern: #"\balot\b"#,
            in: text,
            replacement: "a lot",
            category: .vocabulary,
            explanation: "The standard spelling is ‘a lot.’",
            confidence: 0.99
        ))
        findings.append(contentsOf: replacing(
            pattern: #"\b(could|would|should|might|must)\s+of\b"#,
            in: text,
            replacement: nil,
            category: .agreement,
            explanation: "Use ‘have’ after a modal verb, not ‘of.’",
            confidence: 0.96,
            replacementBuilder: { match, source in
                let modal = (source as NSString).substring(with: match.range(at: 1))
                return "\(modal) have"
            }
        ))
        findings.append(contentsOf: replacing(
            pattern: #"\bin order to\b"#,
            in: text,
            replacement: "to",
            category: .concision,
            explanation: "‘To’ is more concise and keeps the meaning unchanged.",
            confidence: 0.82
        ))
        findings.append(contentsOf: replacing(
            pattern: #"\bmore\s+better\b"#,
            in: text,
            replacement: "better",
            category: .agreement,
            explanation: "Avoid the double comparative ‘more better.’",
            confidence: 0.97
        ))
        findings.append(contentsOf: replacing(
            pattern: #"\bgood\s+in\s+(mathematics|math|English|science)\b"#,
            in: text,
            replacement: nil,
            category: .style,
            explanation: "Use ‘good at’ for ability in a subject.",
            confidence: 0.91,
            replacementBuilder: { match, source in
                let subject = source.substring(with: match.range(at: 1))
                return "good at \(subject)"
            }
        ))
        findings.append(contentsOf: replacing(
            pattern: #"\bif\s+I\s+would\s+know\b"#,
            in: text,
            replacement: "if I knew",
            category: .verbTense,
            explanation: "Use the simple past in this hypothetical if-clause.",
            confidence: 0.91
        ))
        return findings
    }

    private func agreementFindings(in text: String) -> [Suggestion] {
        var findings: [Suggestion] = []
        let singular = try! NSRegularExpression(pattern: #"\b(he|she|it)\s+(have|are|do|were)\b"#, options: [.caseInsensitive])
        for match in singular.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let verb = (text as NSString).substring(with: match.range(at: 2)).lowercased()
            let replacement: String
            switch verb {
            case "have": replacement = "has"
            case "are": replacement = "is"
            case "were": replacement = "was"
            default: replacement = "does"
            }
            findings.append(Suggestion(
                originalText: (text as NSString).substring(with: match.range(at: 2)),
                suggestedText: replacement,
                category: .agreement,
                explanation: "Use a singular verb with ‘\((text as NSString).substring(with: match.range(at: 1)))’. ",
                confidence: 0.93,
                range: TextRange(location: match.range(at: 2).location, length: match.range(at: 2).length)
            ))
        }

        let plural = try! NSRegularExpression(pattern: #"\b(we|they|you)\s+(is|has|does|was)\b"#, options: [.caseInsensitive])
        for match in plural.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let verb = (text as NSString).substring(with: match.range(at: 2)).lowercased()
            let replacement: String
            switch verb {
            case "is": replacement = "are"
            case "has": replacement = "have"
            case "does": replacement = "do"
            default: replacement = "were"
            }
            findings.append(Suggestion(
                originalText: (text as NSString).substring(with: match.range(at: 2)),
                suggestedText: replacement,
                category: .agreement,
                explanation: "Use a plural verb with ‘\((text as NSString).substring(with: match.range(at: 1)))’. ",
                confidence: 0.93,
                range: TextRange(location: match.range(at: 2).location, length: match.range(at: 2).length)
            ))
        }

        let thirdPersonForms: [String: String] = [
            "walk": "walks", "work": "works", "need": "needs", "want": "wants",
            "like": "likes", "seem": "seems", "look": "looks", "go": "goes", "say": "says",
            "tell": "tells", "use": "uses", "know": "knows", "think": "thinks"
        ]
        let basePattern = thirdPersonForms.keys.sorted().joined(separator: "|")
        let thirdPerson = try! NSRegularExpression(
            pattern: #"\b(he|she|it)\s+(?:only\s+)?("# + basePattern + #")\b"#,
            options: [.caseInsensitive]
        )
        for match in thirdPerson.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let original = (text as NSString).substring(with: match.range(at: 2))
            guard let replacement = thirdPersonForms[original.lowercased()] else { continue }
            findings.append(Suggestion(
                originalText: original,
                suggestedText: preserveCase(replacement, like: original),
                category: .agreement,
                explanation: "Use the third-person singular verb form with ‘\((text as NSString).substring(with: match.range(at: 1)))’. ",
                confidence: 0.91,
                range: TextRange(location: match.range(at: 2).location, length: match.range(at: 2).length)
            ))
        }
        return findings
    }

    private func tenseFindings(in text: String) -> [Suggestion] {
        let verbs: [String: String] = [
            "send": "sent", "go": "went", "write": "wrote", "make": "made",
            "see": "saw", "take": "took", "come": "came", "run": "ran",
            "meet": "met", "buy": "bought", "choose": "chose", "eat": "ate",
            "walk": "walked", "work": "worked", "call": "called", "finish": "finished",
            "email": "emailed", "submit": "submitted"
        ]
        let verbPattern = verbs.keys.sorted().joined(separator: "|")
        let timePattern = #"(?:already|yesterday|last\s+(?:night|week|month)|\d+\s+days?\s+ago)"#
        let beforeTime = try! NSRegularExpression(
            pattern: #"\b("# + timePattern + #")\s+("# + verbPattern + #")\b"#,
            options: [.caseInsensitive]
        )
        let afterTime = try! NSRegularExpression(
            pattern: #"(?<!to\s)\b("# + verbPattern + #")\b(?=[^.!?]{0,50}\b"# + timePattern + #"\b)"#,
            options: [.caseInsensitive]
        )

        var findings: [Suggestion] = []
        for match in beforeTime.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            guard match.numberOfRanges > 2 else { continue }
            appendTenseFinding(for: match.range(at: 2), in: text, verbs: verbs, to: &findings)
        }
        for match in afterTime.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            guard match.numberOfRanges > 1 else { continue }
            appendTenseFinding(for: match.range(at: 1), in: text, verbs: verbs, to: &findings)
        }
        findings.append(contentsOf: complexTenseFindings(in: text))
        return findings
    }

    private func complexTenseFindings(in text: String) -> [Suggestion] {
        var findings: [Suggestion] = []
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let source = text as NSString

        let pastPerfect = try! NSRegularExpression(
            pattern: #"\b(has|have)(?=\s+(?:been\s+)?[A-Za-z]+(?:ed|en|ing)\b[^.!?]{0,80}\bbefore\b[^.!?]{0,80}\b(?:began|started|ended|arrived|left|called|opened|closed)\b)"#,
            options: [.caseInsensitive]
        )
        for match in pastPerfect.matches(in: text, range: fullRange) {
            let range = match.range(at: 1)
            findings.append(tenseSuggestion(
                original: source.substring(with: range),
                replacement: "had",
                explanation: "Use the past perfect for the earlier of two completed past actions.",
                range: range,
                confidence: 0.92
            ))
        }

        let futureAuxiliary = try! NSRegularExpression(pattern: #"\bwill\s+(has|had)\b"#, options: [.caseInsensitive])
        for match in futureAuxiliary.matches(in: text, range: fullRange) {
            let range = match.range(at: 1)
            findings.append(tenseSuggestion(
                original: source.substring(with: range),
                replacement: "have",
                explanation: "Use ‘have’ after the modal verb ‘will.’",
                range: range,
                confidence: 0.97
            ))
        }

        let futureBases: [String: String] = [
            "goes": "go", "works": "work", "needs": "need", "wants": "want",
            "likes": "like", "does": "do", "is": "be", "are": "be"
        ]
        let futureBasePattern = futureBases.keys.sorted().joined(separator: "|")
        let futureSimple = try! NSRegularExpression(
            pattern: #"\bwill\s+("# + futureBasePattern + #")\b"#,
            options: [.caseInsensitive]
        )
        for match in futureSimple.matches(in: text, range: fullRange) {
            let range = match.range(at: 1)
            let original = source.substring(with: range)
            guard let replacement = futureBases[original.lowercased()] else { continue }
            findings.append(tenseSuggestion(
                original: original,
                replacement: replacement,
                explanation: "Use the base verb form after ‘will.’",
                range: range,
                confidence: 0.96
            ))
        }

        let progressiveForms: [String: String] = [
            "work": "working", "read": "reading", "write": "writing", "run": "running",
            "study": "studying", "wait": "waiting", "travel": "traveling", "sleep": "sleeping"
        ]
        let progressivePattern = progressiveForms.keys.sorted().joined(separator: "|")
        let progressive = try! NSRegularExpression(
            pattern: #"\bwill\s+(?:have\s+been|be)\s+("# + progressivePattern + #")\b"#,
            options: [.caseInsensitive]
        )
        for match in progressive.matches(in: text, range: fullRange) {
            let range = match.range(at: 1)
            let original = source.substring(with: range)
            guard let replacement = progressiveForms[original.lowercased()] else { continue }
            findings.append(tenseSuggestion(
                original: original,
                replacement: replacement,
                explanation: "Use the -ing form in a continuous tense.",
                range: range,
                confidence: 0.96
            ))
        }
        return findings
    }

    private func tenseSuggestion(
        original: String,
        replacement: String,
        explanation: String,
        range: NSRange,
        confidence: Double
    ) -> Suggestion {
        Suggestion(
            originalText: original,
            suggestedText: preserveCase(replacement, like: original),
            category: .verbTense,
            explanation: explanation,
            confidence: confidence,
            range: TextRange(location: range.location, length: range.length)
        )
    }

    private func appendTenseFinding(
        for range: NSRange,
        in text: String,
        verbs: [String: String],
        to findings: inout [Suggestion]
    ) {
        let verb = (text as NSString).substring(with: range)
        guard let past = verbs[verb.lowercased()] else { return }
        findings.append(Suggestion(
            originalText: verb,
            suggestedText: preserveCase(past, like: verb),
            category: .verbTense,
            explanation: "A completed past-time phrase usually takes the past tense.",
            confidence: 0.95,
            range: TextRange(location: range.location, length: range.length)
        ))
    }

    private func articleFindings(in text: String) -> [Suggestion] {
        var findings: [Suggestion] = []
        let aRegex = try! NSRegularExpression(pattern: #"\ba\s+([aeiou][A-Za-z]+)\b"#, options: [.caseInsensitive])
        for match in aRegex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let articleRange = NSRange(location: match.range(at: 0).location, length: 1)
            findings.append(Suggestion(
                originalText: "a",
                suggestedText: "an",
                category: .articleUsage,
                explanation: "Use ‘an’ before a vowel sound.",
                confidence: 0.78,
                range: TextRange(location: articleRange.location, length: articleRange.length)
            ))
        }

        let missingArticle = try! NSRegularExpression(
            pattern: #"\b(give|show|send|provide|offer)\s+(?:(me|us|him|her|them)\s+)?(example|idea|answer|update|option|explanation)\b"#,
            options: [.caseInsensitive]
        )
        for match in missingArticle.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            guard match.numberOfRanges > 3 else { continue }
            let nounRange = match.range(at: 3)
            let noun = (text as NSString).substring(with: nounRange)
            let article = noun.first.map { "aeiou".contains($0.lowercased()) } == true ? "an" : "a"
            findings.append(Suggestion(
                originalText: noun,
                suggestedText: "\(article) \(noun)",
                category: .articleUsage,
                explanation: "A singular countable noun needs an article here.",
                confidence: 0.91,
                range: TextRange(location: nounRange.location, length: nounRange.length)
            ))
        }
        return findings
    }

    private func questionEndingFindings(in text: String) -> [Suggestion] {
        let questionStart = try! NSRegularExpression(
            pattern: #"^\s*(can|could|would|will|do|does|did|is|are|was|were|what|why|how|when|where|who)\b"#,
            options: [.caseInsensitive]
        )
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard questionStart.firstMatch(in: text, range: fullRange) != nil else { return [] }

        let source = text as NSString
        let trailingComma = try! NSRegularExpression(pattern: #"\s*,\s*$"#)
        if let match = trailingComma.firstMatch(in: text, range: fullRange) {
            return [Suggestion(
                originalText: source.substring(with: match.range),
                suggestedText: "?",
                category: .punctuation,
                explanation: "Use a question mark to end a direct question.",
                confidence: 0.98,
                range: TextRange(location: match.range.location, length: match.range.length)
            )]
        }

        let trimmedLength = source.length - (text as NSString).rangeOfCharacter(
            from: CharacterSet.whitespacesAndNewlines.inverted,
            options: .backwards
        ).location - 1
        let contentEnd = max(0, source.length - max(0, trimmedLength))
        guard contentEnd > 0 else { return [] }
        let finalCharacter = source.substring(with: NSRange(location: contentEnd - 1, length: 1))
        guard !".?!".contains(finalCharacter) else { return [] }
        return [Suggestion(
            originalText: "",
            suggestedText: "?",
            category: .punctuation,
            explanation: "Use a question mark to end a direct question.",
            confidence: 0.95,
            range: TextRange(location: contentEnd, length: 0)
        )]
    }

    private func punctuationFindings(in text: String) -> [Suggestion] {
        var findings: [Suggestion] = []
        let spaces = try! NSRegularExpression(pattern: #" {2,}"#)
        for match in spaces.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            findings.append(Suggestion(
                originalText: (text as NSString).substring(with: match.range),
                suggestedText: " ",
                category: .punctuation,
                explanation: "Use a single space between words.",
                confidence: 0.98,
                range: TextRange(location: match.range.location, length: match.range.length)
            ))
        }
        let beforeComma = try! NSRegularExpression(pattern: #"\s+,"#)
        for match in beforeComma.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            findings.append(Suggestion(
                originalText: (text as NSString).substring(with: match.range),
                suggestedText: ",",
                category: .punctuation,
                explanation: "Place the comma directly after the preceding word.",
                confidence: 0.95,
                range: TextRange(location: match.range.location, length: match.range.length)
            ))
        }
        return findings
    }

    private func replacing(
        pattern: String,
        in text: String,
        replacement: String?,
        category: PatternCategory,
        explanation: String,
        confidence: Double,
        replacementBuilder: ((NSTextCheckingResult, NSString) -> String)? = nil
    ) -> [Suggestion] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).map { match in
            let original = source.substring(with: match.range)
            let rawValue = replacementBuilder?(match, source) ?? replacement ?? ""
            let value = preserveCase(rawValue, like: original)
            return Suggestion(
                originalText: original,
                suggestedText: value,
                category: category,
                explanation: explanation,
                confidence: confidence,
                range: TextRange(location: match.range.location, length: match.range.length)
            )
        }
    }

    private func removeOverlappingFindings(_ findings: [Suggestion]) -> [Suggestion] {
        let sorted = findings.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
        var accepted: [Suggestion] = []
        for finding in sorted {
            let overlaps = accepted.contains { existing in
                if NSIntersectionRange(existing.range.nsRange, finding.range.nsRange).length > 0 {
                    return true
                }
                if existing.requiresClarification || finding.requiresClarification {
                    let clarification = existing.requiresClarification ? existing.range.nsRange : finding.range.nsRange
                    let other = existing.requiresClarification ? finding.range.nsRange : existing.range.nsRange
                    return other.location >= clarification.location && other.location <= NSMaxRange(clarification)
                }
                return false
            }
            if !overlaps { accepted.append(finding) }
        }
        return accepted.sorted { $0.range.location < $1.range.location }
    }

    private func preserveCase(_ replacement: String, like source: String) -> String {
        guard source.first?.isUppercase == true else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}

final class PersonalizationEngine {
    func rank(
        _ suggestions: [Suggestion],
        using profile: WritingProfile,
        applicationBundleID: String? = nil,
        tonePreference: TonePreference = .preserveVoice
    ) -> [Suggestion] {
        let ranked = suggestions.compactMap { suggestion -> Suggestion? in
            var copy = suggestion
            let suggestionKey = PatternGeneralizer.key(
                category: suggestion.category,
                before: suggestion.originalText,
                after: suggestion.suggestedText
            )

            let candidates = profile.patterns.compactMap { pattern -> (LearnedPattern, Double)? in
                guard pattern.isReliable, pattern.category == suggestion.category else { return nil }

                let exactBefore = PatternGeneralizer.normalized(pattern.exampleBefore) ==
                    PatternGeneralizer.normalized(suggestion.originalText)
                let exactAfter = PatternGeneralizer.normalized(pattern.exampleAfter) ==
                    PatternGeneralizer.normalized(suggestion.suggestedText)
                let patternKey = pattern.generalizedKey ?? PatternGeneralizer.key(
                    category: pattern.category,
                    before: pattern.exampleBefore,
                    after: pattern.exampleAfter
                )
                let generalizedMatch = patternKey == suggestionKey
                guard exactBefore || exactAfter || generalizedMatch else { return nil }

                // A pattern observed in only one application remains scoped to
                // that application unless the exact correction is repeated.
                if let scopedApp = pattern.applicationBundleID,
                   scopedApp != applicationBundleID,
                   !(exactBefore && exactAfter) {
                    return nil
                }

                var score = pattern.confidence
                if exactBefore && exactAfter { score += 0.5 }
                else if generalizedMatch { score += 0.28 }
                if pattern.applicationBundleID == applicationBundleID { score += 0.12 }
                return (pattern, score)
            }

            if let pattern = candidates.max(by: { $0.1 < $1.1 })?.0 {
                copy.isPersonalized = true
                copy.patternID = pattern.id
                var boost = pattern.confidence * 0.15
                if pattern.applicationBundleID == applicationBundleID { boost += 0.03 }
                copy.confidence = min(0.99, suggestion.confidence + boost)
                let appPhrase = pattern.applicationBundleID == applicationBundleID
                    ? " in this application"
                    : ""
                copy.personalizationReason = "You made this kind of correction \(pattern.occurrenceCount) times\(appPhrase)."
            }

            let matchingPreferences = (profile.suggestionPreferences ?? []).filter { preference in
                preference.generalizedKey == suggestionKey &&
                    preference.category == suggestion.category &&
                    (preference.applicationBundleID == nil || preference.applicationBundleID == applicationBundleID)
            }
            if matchingPreferences.contains(where: {
                $0.rejectionCount >= 3 && $0.rejectionCount > $0.acceptanceCount
            }) {
                return nil
            }
            if !copy.isPersonalized,
               let acceptedPreference = matchingPreferences.max(by: {
                   $0.acceptanceCount < $1.acceptanceCount
               }),
               acceptedPreference.acceptanceCount >= 2,
               acceptedPreference.acceptanceCount > acceptedPreference.rejectionCount {
                copy.isPersonalized = true
                copy.confidence = min(0.99, copy.confidence + 0.06)
                copy.personalizationReason = "You accepted this kind of suggestion \(acceptedPreference.acceptanceCount) times."
            }

            let stronglyRejectedPattern = profile.patterns.contains { pattern in
                guard pattern.enabled,
                      pattern.category == suggestion.category,
                      pattern.rejectionCount >= 3,
                      pattern.rejectionCount > pattern.acceptanceCount else { return false }
                let patternKey = pattern.generalizedKey ?? PatternGeneralizer.key(
                    category: pattern.category,
                    before: pattern.exampleBefore,
                    after: pattern.exampleAfter
                )
                let appMatches = pattern.applicationBundleID == nil || pattern.applicationBundleID == applicationBundleID
                return patternKey == suggestionKey && appMatches
            }
            if stronglyRejectedPattern { return nil }

            switch tonePreference {
            case .concise where copy.category == .concision:
                copy.confidence = min(0.99, copy.confidence + 0.08)
            case .preserveVoice where copy.category == .style && copy.confidence < 0.86:
                return nil
            case .formal where copy.category == .style:
                copy.confidence = min(0.99, copy.confidence + 0.04)
            default:
                break
            }
            return copy
        }

        return ranked.sorted {
            if $0.isPersonalized != $1.isPersonalized { return $0.isPersonalized }
            return $0.confidence > $1.confidence
        }
    }
}

struct TextDiffEngine {
    private struct Token {
        let value: String
        let range: NSRange
    }

    func diff(before: String, after: String) -> CorrectionDiff {
        diffs(before: before, after: after).first ?? CorrectionDiff(
            before: "",
            after: "",
            isMeaningful: false
        )
    }

    /// Produces one event for each non-overlapping token-level edit. Whitespace
    /// is intentionally excluded so formatting-only changes do not become
    /// personal writing patterns.
    func diffs(before: String, after: String) -> [CorrectionDiff] {
        guard before != after else { return [] }
        let oldTokens = tokenize(before)
        let newTokens = tokenize(after)

        let oldValues = oldTokens.map(\.value)
        let newValues = newTokens.map(\.value)
        if oldValues == newValues { return [] }

        let oldWords = oldValues.map { $0.lowercased() }
        let newWords = newValues.map { $0.lowercased() }
        if oldWords.count > 1,
           oldWords.count == newWords.count,
           oldWords.sorted() == newWords.sorted(),
           oldWords != newWords {
            var prefix = 0
            while prefix < oldWords.count && oldWords[prefix] == newWords[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < oldWords.count - prefix &&
                    oldWords[oldWords.count - suffix - 1] == newWords[newWords.count - suffix - 1] {
                suffix += 1
            }
            let oldFragment = fragment(
                from: oldTokens,
                start: prefix,
                end: oldTokens.count - suffix,
                source: before
            )
            let newFragment = fragment(
                from: newTokens,
                start: prefix,
                end: newTokens.count - suffix,
                source: after
            )
            return [CorrectionDiff(
                before: oldFragment,
                after: newFragment,
                isMeaningful: true,
                classification: .wordOrder
            )]
        }

        if oldTokens.isEmpty || newTokens.isEmpty {
            let oldValue = before.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = after.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !oldValue.isEmpty || !newValue.isEmpty else { return [] }
            return [CorrectionDiff(
                before: oldValue,
                after: newValue,
                isMeaningful: true,
                classification: classify(before: oldValue, after: newValue)
            )]
        }

        let matches = lcsMatches(oldTokens.map(\.value), newTokens.map(\.value)) + [(oldTokens.count, newTokens.count)]
        var oldCursor = 0
        var newCursor = 0
        var results: [CorrectionDiff] = []

        for (oldMatch, newMatch) in matches {
            if oldCursor < oldMatch || newCursor < newMatch {
                let oldCount = oldMatch - oldCursor
                let newCount = newMatch - newCursor
                if oldCount == newCount && oldCount > 1 {
                    // Adjacent one-for-one replacements such as “have a” →
                    // “has an” are separate reusable corrections.
                    for offset in 0..<oldCount {
                        let oldFragment = oldTokens[oldCursor + offset].value
                        let newFragment = newTokens[newCursor + offset].value
                        if normalize(oldFragment) != normalize(newFragment) {
                            results.append(CorrectionDiff(
                                before: oldFragment,
                                after: newFragment,
                                isMeaningful: true,
                                classification: classify(before: oldFragment, after: newFragment)
                            ))
                        }
                    }
                } else {
                    let oldFragment = fragment(from: oldTokens, start: oldCursor, end: oldMatch, source: before)
                    let newFragment = fragment(from: newTokens, start: newCursor, end: newMatch, source: after)
                    let normalizedBefore = normalize(oldFragment)
                    let normalizedAfter = normalize(newFragment)
                    if normalizedBefore != normalizedAfter && (!normalizedBefore.isEmpty || !normalizedAfter.isEmpty) {
                        results.append(CorrectionDiff(
                            before: oldFragment,
                            after: newFragment,
                            isMeaningful: true,
                            classification: classify(before: oldFragment, after: newFragment)
                        ))
                    }
                }
            }
            oldCursor = oldMatch + 1
            newCursor = newMatch + 1
        }
        return results
    }

    private func tokenize(_ text: String) -> [Token] {
        let source = text as NSString
        let regex = try! NSRegularExpression(
            pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*|[^\s\p{L}\p{N}]"#
        )
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            Token(value: source.substring(with: $0.range), range: $0.range)
        }
    }

    private func lcsMatches(_ old: [String], _ new: [String]) -> [(Int, Int)] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        if !old.isEmpty && !new.isEmpty {
            for i in stride(from: old.count - 1, through: 0, by: -1) {
                for j in stride(from: new.count - 1, through: 0, by: -1) {
                    if old[i] == new[j] {
                        lengths[i][j] = lengths[i + 1][j + 1] + 1
                    } else {
                        lengths[i][j] = max(lengths[i + 1][j], lengths[i][j + 1])
                    }
                }
            }
        }

        var i = 0
        var j = 0
        var matches: [(Int, Int)] = []
        while i < old.count && j < new.count {
            if old[i] == new[j] {
                matches.append((i, j))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return matches
    }

    private func fragment(from tokens: [Token], start: Int, end: Int, source: String) -> String {
        guard start < end, start < tokens.count else { return "" }
        let last = min(end - 1, tokens.count - 1)
        let range = NSRange(
            location: tokens[start].range.location,
            length: NSMaxRange(tokens[last].range) - tokens[start].range.location
        )
        return (source as NSString).substring(with: range)
    }

    private func classify(before: String, after: String) -> EditClassification {
        let before = normalize(before)
        let after = normalize(after)
        if before.isEmpty { return .insertion }
        if after.isEmpty { return .deletion }
        if before.lowercased() == after.lowercased() && before != after { return .capitalization }

        let oldWords = wordTokens(before)
        let newWords = wordTokens(after)
        if oldWords.count > 1,
           oldWords.count == newWords.count,
           oldWords.sorted() == newWords.sorted(),
           oldWords != newWords {
            return .wordOrder
        }
        if punctuationAndWhitespaceOnly(before) || punctuationAndWhitespaceOnly(after) {
            return .punctuation
        }
        return .replacement
    }

    private func wordTokens(_ value: String) -> [String] {
        value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private func punctuationAndWhitespaceOnly(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) ||
                CharacterSet.symbols.contains($0) ||
                CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
