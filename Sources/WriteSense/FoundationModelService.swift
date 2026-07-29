import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceModelStatus: Equatable {
    case available
    case requiresMacOS26
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case frameworkUnavailable

    var isAvailable: Bool { self == .available }

    var title: String {
        switch self {
        case .available: return "Apple Intelligence ready"
        case .requiresMacOS26: return "Deep Review requires macOS 26"
        case .deviceNotEligible: return "This Mac does not support Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Enable Apple Intelligence for Deep Review"
        case .modelNotReady: return "Apple Intelligence model is downloading"
        case .frameworkUnavailable: return "Foundation Models is unavailable"
        }
    }
}

enum FoundationModelServiceError: LocalizedError {
    case unavailable(OnDeviceModelStatus)
    case noUsableSuggestions

    var errorDescription: String? {
        switch self {
        case .unavailable(let status): return status.title
        case .noUsableSuggestions: return "Apple Intelligence found no additional corrections."
        }
    }
}

@MainActor
final class FoundationModelWritingService {
    var status: OnDeviceModelStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable:
                return .frameworkUnavailable
            @unknown default:
                return .frameworkUnavailable
            }
        }
        return .requiresMacOS26
        #else
        return .frameworkUnavailable
        #endif
    }

    func review(_ text: String, profile: WritingProfile) async throws -> [Suggestion] {
        let currentStatus = status
        guard currentStatus.isAvailable else {
            throw FoundationModelServiceError.unavailable(currentStatus)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let suggestions = try await reviewWithSystemModel(text, profile: profile)
            guard !suggestions.isEmpty else { throw FoundationModelServiceError.noUsableSuggestions }
            return suggestions
        }
        #endif
        throw FoundationModelServiceError.unavailable(currentStatus)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func reviewWithSystemModel(_ text: String, profile: WritingProfile) async throws -> [Suggestion] {
        let session = LanguageModelSession(instructions: """
            You are WriteSense, a careful English writing coach running privately on the user's Mac.
            Identify concrete spelling, grammar, punctuation, clarity, and concision problems.
            Preserve the writer's meaning, voice, names, technical terminology, timeframe, and intended tense/aspect.
            Never infer unstated past or future context and never change a valid present tense merely to another valid tense.
            When an auxiliary tense construction is malformed, preserve its auxiliaries and repair the verb form.
            For two explicitly completed past actions linked by “before,” check whether the earlier action needs past perfect.
            Use subject pronouns in compound subjects and remove redundant comparative forms.
            Never invent facts. Return at most eight high-confidence corrections.
            Every originalText must be an exact, non-empty substring copied from the supplied paragraph.
            replacement must contain only the text that should replace originalText.
            If the paragraph is already correct, return an empty suggestions array.
            """)

        let reliablePatterns = profile.patterns
            .filter(\.isReliable)
            .prefix(8)
            .map { "- \($0.category.title): ‘\($0.exampleBefore)’ → ‘\($0.exampleAfter)’" }
            .joined(separator: "\n")
        let personalContext = reliablePatterns.isEmpty
            ? "No reliable personal patterns are available yet."
            : "Relevant personal patterns:\n\(reliablePatterns)"

        let prompt = """
            Review only the paragraph between <paragraph> tags.
            \(personalContext)

            <paragraph>
            \(text)
            </paragraph>
            """
        let response = try await session.respond(to: prompt, generating: ModelWritingReview.self)
        return validatedSuggestions(from: response.content.suggestions, in: text)
    }

    @available(macOS 26.0, *)
    private func validatedSuggestions(from items: [ModelWritingIssue], in text: String) -> [Suggestion] {
        let source = text as NSString
        var usedRanges: [NSRange] = []
        var suggestions: [Suggestion] = []

        for item in items.prefix(8) {
            let original = item.originalText
            let replacement = item.replacement
            guard !original.isEmpty, original != replacement else { continue }

            var searchLocation = 0
            var selectedRange = NSRange(location: NSNotFound, length: 0)
            while searchLocation < source.length {
                let searchRange = NSRange(location: searchLocation, length: source.length - searchLocation)
                let candidate = source.range(of: original, options: [], range: searchRange)
                guard candidate.location != NSNotFound else { break }
                if !usedRanges.contains(where: { NSIntersectionRange($0, candidate).length > 0 }) {
                    selectedRange = candidate
                    break
                }
                searchLocation = candidate.location + max(candidate.length, 1)
            }
            guard selectedRange.location != NSNotFound else { continue }

            usedRanges.append(selectedRange)
            suggestions.append(Suggestion(
                originalText: original,
                suggestedText: replacement,
                category: category(for: item.category),
                explanation: item.explanation,
                confidence: 0.86,
                range: TextRange(location: selectedRange.location, length: selectedRange.length),
                personalizationReason: "Reviewed privately on-device with Apple Intelligence."
            ))
        }
        return suggestions
    }

    @available(macOS 26.0, *)
    private func category(for value: String) -> PatternCategory {
        switch value.lowercased() {
        case "spelling": return .spelling
        case "grammar", "agreement": return .agreement
        case "tense": return .verbTense
        case "article": return .articleUsage
        case "punctuation": return .punctuation
        case "capitalization": return .capitalization
        case "clarity": return .clarity
        case "concision": return .concision
        case "vocabulary": return .vocabulary
        default: return .style
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable(description: "A structured review of one English paragraph")
private struct ModelWritingReview {
    @Guide(description: "Zero to eight concrete, non-overlapping writing corrections")
    var suggestions: [ModelWritingIssue]
}

@available(macOS 26.0, *)
@Generable(description: "One precise correction to the supplied paragraph")
private struct ModelWritingIssue {
    @Guide(description: "An exact, non-empty substring copied verbatim from the paragraph")
    var originalText: String

    @Guide(description: "The text that should replace originalText")
    var replacement: String

    @Guide(description: "A short, useful explanation of the correction")
    var explanation: String

    @Guide(description: "One category: spelling, grammar, agreement, tense, article, punctuation, capitalization, clarity, concision, vocabulary, or style")
    var category: String
}
#endif
